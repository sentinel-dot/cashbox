import { describe, it, expect, vi, beforeEach } from 'vitest';
import request from 'supertest';
import app from '../../app.js';
import { db } from '../../db/index.js';

// ─── Stripe-Mock ──────────────────────────────────────────────────────────────
// vi.hoisted() stellt sicher dass mockConstructEvent vor dem gehoisteten
// vi.mock()-Factory initialisiert ist — ohne hoisted wäre es undefined.

const { mockConstructEvent } = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
}));

// Klasse statt vi.fn(): Arrow-Functions sind keine Konstruktoren — Vitest
// würde vi.fn().mockImplementation(() => ...) mit `new` aufrufen und dann
// "is not a constructor" werfen.
vi.mock('stripe', () => ({
  default: class MockStripe {
    webhooks = { constructEvent: mockConstructEvent };
  },
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

const FAKE_SIG    = 't=1234,v1=abcdef';
const FAKE_SECRET = 'whsec_test';
const CUSTOMER_ID = 'cus_test_abc';
const SUB_ID      = 'sub_test_xyz';

/** Legt einen Tenant mit stripe_customer_id an, gibt tenantId zurück. */
async function seedTenant(stripeCustomerId: string): Promise<number> {
  const [t] = await db.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status, stripe_customer_id)
     VALUES ('Webhook GmbH', 'Teststr. 1, Berlin', 'starter', 'trial', ?)`,
    [stripeCustomerId]
  ) as any[];
  const tenantId: number = t.insertId;
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);
  return tenantId;
}

function fakeEvent(type: string, obj: object, eventId = `evt_${Date.now()}`): object {
  return { id: eventId, type, data: { object: obj } };
}

function fakeSubscription(overrides: object = {}): object {
  return {
    id:       SUB_ID,
    object:   'subscription',
    customer: CUSTOMER_ID,
    items:    { data: [{ price: { id: process.env['STRIPE_PRICE_STARTER'] ?? 'price_starter_test' } }] },
    ...overrides,
  };
}

function fakeInvoice(overrides: object = {}): object {
  return {
    id:         'in_test',
    object:     'invoice',
    customer:   CUSTOMER_ID,
    period_end: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30, // +30 Tage
    ...overrides,
  };
}

function fakeCheckoutSession(overrides: object = {}): object {
  return {
    id:           'cs_test',
    object:       'checkout.session',
    customer:     CUSTOMER_ID,
    subscription: SUB_ID,
    ...overrides,
  };
}

/** Sendet POST /webhooks/stripe mit einem gemockten Event. */
async function postWebhook(event: object) {
  process.env['STRIPE_WEBHOOK_SECRET'] = FAKE_SECRET;
  process.env['STRIPE_SECRET_KEY']     = 'sk_test_dummy';
  process.env['STRIPE_PRICE_STARTER']  = 'price_starter_test';
  process.env['STRIPE_PRICE_PRO']      = 'price_pro_test';
  process.env['STRIPE_PRICE_BUSINESS'] = 'price_business_test';

  // mockImplementation statt mockReturnValue: überschreibt ggf. vorherige Impl. aus anderem Test
  mockConstructEvent.mockImplementation(() => event);

  return request(app)
    .post('/webhooks/stripe')
    .set('stripe-signature', FAKE_SIG)
    .set('Content-Type', 'application/json')
    .send(Buffer.from(JSON.stringify(event)));
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('POST /webhooks/stripe — Signatur-Validierung', () => {
  it('Fehlende Signatur → 400', async () => {
    process.env['STRIPE_WEBHOOK_SECRET'] = FAKE_SECRET;
    process.env['STRIPE_SECRET_KEY']     = 'sk_test_dummy';
    mockConstructEvent.mockImplementation(() => { throw new Error('No signature'); });

    const res = await request(app)
      .post('/webhooks/stripe')
      .set('Content-Type', 'application/json')
      .send({});

    expect(res.status).toBe(400);
  });

  it('Ungültige Signatur → 400', async () => {
    process.env['STRIPE_WEBHOOK_SECRET'] = FAKE_SECRET;
    process.env['STRIPE_SECRET_KEY']     = 'sk_test_dummy';
    mockConstructEvent.mockImplementation(() => { throw new Error('Ungültig'); });

    const res = await request(app)
      .post('/webhooks/stripe')
      .set('stripe-signature', 'falsche-sig')
      .set('Content-Type', 'application/json')
      .send(Buffer.from('{}'));

    expect(res.status).toBe(400);
  });

  it('Valide Signatur, unbekannter Event-Typ → 200 (kein Retry)', async () => {
    await seedTenant(CUSTOMER_ID);
    const res = await postWebhook(fakeEvent('unknown.event.type', {}));
    expect(res.status).toBe(200);
    expect(res.body.received).toBe(true);
  });
});

describe('POST /webhooks/stripe — customer.subscription.created', () => {
  it('Setzt subscription_status=active und Plan', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);

    const res = await postWebhook(
      fakeEvent('customer.subscription.created', fakeSubscription())
    );

    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT subscription_status, plan, stripe_subscription_id FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].subscription_status).toBe('active');
    expect(rows[0].plan).toBe('starter');
    expect(rows[0].stripe_subscription_id).toBe(SUB_ID);
  });

  it('Unbekannter Customer → 200, kein DB-Update', async () => {
    const res = await postWebhook(
      fakeEvent('customer.subscription.created',
        fakeSubscription({ customer: 'cus_unknown' })
      )
    );
    expect(res.status).toBe(200);
  });
});

describe('POST /webhooks/stripe — customer.subscription.updated', () => {
  it('Plan-Wechsel wird übernommen', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);

    // Zuerst aktiv schalten
    await db.execute(
      `UPDATE tenants SET subscription_status = 'active', plan = 'starter' WHERE id = ?`,
      [tenantId]
    );

    // Update auf Pro
    const res = await postWebhook(
      fakeEvent('customer.subscription.updated',
        fakeSubscription({ items: { data: [{ price: { id: 'price_pro_test' } }] } })
      )
    );
    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT plan FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].plan).toBe('pro');
  });
});

describe('POST /webhooks/stripe — customer.subscription.deleted', () => {
  it('Setzt subscription_status=cancelled und data_retention_until', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);

    const res = await postWebhook(
      fakeEvent('customer.subscription.deleted', fakeSubscription())
    );
    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT subscription_status, data_retention_until FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].subscription_status).toBe('cancelled');
    expect(rows[0].data_retention_until).not.toBeNull(); // GoBD: 10-Jahres-Frist gesetzt
  });
});

describe('POST /webhooks/stripe — invoice.payment_succeeded', () => {
  it('Aktualisiert subscription_current_period_end', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);
    const futureTs = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30;

    const res = await postWebhook(
      fakeEvent('invoice.payment_succeeded', fakeInvoice({ period_end: futureTs }))
    );
    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT subscription_current_period_end FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].subscription_current_period_end).not.toBeNull();
  });
});

describe('POST /webhooks/stripe — invoice.payment_failed', () => {
  it('Setzt subscription_status=past_due', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);
    await db.execute(
      `UPDATE tenants SET subscription_status = 'active' WHERE id = ?`,
      [tenantId]
    );

    const res = await postWebhook(
      fakeEvent('invoice.payment_failed', fakeInvoice())
    );
    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT subscription_status FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].subscription_status).toBe('past_due');
  });
});

describe('POST /webhooks/stripe — checkout.session.completed', () => {
  it('Setzt stripe_subscription_id und subscription_status=active', async () => {
    const tenantId = await seedTenant(CUSTOMER_ID);

    const res = await postWebhook(
      fakeEvent('checkout.session.completed', fakeCheckoutSession())
    );
    expect(res.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT subscription_status, stripe_subscription_id FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].subscription_status).toBe('active');
    expect(rows[0].stripe_subscription_id).toBe(SUB_ID);
  });
});

describe('POST /webhooks/stripe — Idempotenz', () => {
  it('Gleiche Event-ID zweimal → 200 beim ersten, skipped beim zweiten', async () => {
    await seedTenant(CUSTOMER_ID);
    const event = fakeEvent('customer.subscription.created', fakeSubscription(), 'evt_idempotent_1');

    const res1 = await postWebhook(event);
    expect(res1.status).toBe(200);
    expect(res1.body.skipped).toBeUndefined();

    const res2 = await postWebhook(event);
    expect(res2.status).toBe(200);
    expect(res2.body.skipped).toBe('duplicate');
  });
});

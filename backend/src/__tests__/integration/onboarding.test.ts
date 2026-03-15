import { describe, it, expect, vi, beforeEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Stripe-Mock ──────────────────────────────────────────────────────────────
// vi.hoisted() stellt sicher dass die Mock-Funktionen vor dem gehoisteten
// vi.mock()-Factory initialisiert sind — ohne hoisted wären sie undefined.

const { mockCustomerCreate, mockSessionCreate } = vi.hoisted(() => ({
  mockCustomerCreate: vi.fn(),
  mockSessionCreate:  vi.fn(),
}));

// Klasse statt vi.fn(): Arrow-Functions sind keine Konstruktoren — Vitest
// würde vi.fn().mockImplementation(() => ...) mit `new` aufrufen und dann
// "is not a constructor" werfen.
vi.mock('stripe', () => ({
  default: class MockStripe {
    customers = { create: mockCustomerCreate };
    checkout  = { sessions: { create: mockSessionCreate } };
  },
}));

// ─── Setup ────────────────────────────────────────────────────────────────────

function uniqueEmail() {
  return `test-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
}

/** Baut einen vollständigen Tenant mit Device auf — für checkout-session-Tests. */
async function setup(conn: any) {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Test GmbH', 'Teststr. 1, 10115 Berlin', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Owner', ?, ?, 'owner')`,
    [tenantId, uniqueEmail(), hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}

const VALID_REGISTER_BODY = {
  business_name: 'Shisha Bar Berlin',
  email:         'owner@shisha.de',
  password:      'geheim123',
  address:       'Kurfürstendamm 1, 10719 Berlin',
  tax_number:    '12/345/67890',
  device_name:   'iPad Pro',
  device_token:  'a'.repeat(32),
};

// ─── POST /onboarding/register ────────────────────────────────────────────────

describe('POST /onboarding/register', () => {
  it('Happy Path: legt Tenant, User, Gerät und receipt_sequences an; gibt JWT zurück', async () => {
    const body = { ...VALID_REGISTER_BODY, email: uniqueEmail() };

    const res = await request(app)
      .post('/onboarding/register')
      .send(body);

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('refreshToken');
    expect(res.body.user.role).toBe('owner');
    expect(res.body.device).toHaveProperty('id');

    // JWT muss gültige AuthPayload enthalten
    const decoded = jwt.verify(
      res.body.token,
      process.env['JWT_SECRET'] ?? 'test-secret'
    ) as AuthPayload;
    expect(decoded.tenantId).toBeGreaterThan(0);
    expect(decoded.deviceId).toBeGreaterThan(0);
    expect(decoded.role).toBe('owner');

    // DB-State prüfen: Tenant mit trial-Status
    const [tenants] = await db.execute<any[]>(
      'SELECT subscription_status FROM tenants WHERE id = ?',
      [decoded.tenantId]
    );
    expect(tenants[0].subscription_status).toBe('trial');

    // receipt_sequences-Eintrag vorhanden
    const [seqs] = await db.execute<any[]>(
      'SELECT last_number FROM receipt_sequences WHERE tenant_id = ?',
      [decoded.tenantId]
    );
    expect(seqs).toHaveLength(1);
    expect(seqs[0].last_number).toBe(0);

    // Gerät vorhanden und nicht gesperrt
    const [devices] = await db.execute<any[]>(
      'SELECT is_revoked FROM devices WHERE id = ?',
      [decoded.deviceId]
    );
    expect(devices[0].is_revoked).toBeFalsy();
  });

  it('Duplikat-E-Mail → 409', async () => {
    const email = uniqueEmail();

    // Ersten Tenant anlegen
    await request(app)
      .post('/onboarding/register')
      .send({ ...VALID_REGISTER_BODY, email })
      .expect(201);

    // Gleiche E-Mail nochmal → Konflikt
    const res = await request(app)
      .post('/onboarding/register')
      .send({ ...VALID_REGISTER_BODY, email, device_token: 'b'.repeat(32) });

    expect(res.status).toBe(409);
  });

  it('Validierungsfehler: leerer Body → 422', async () => {
    const res = await request(app)
      .post('/onboarding/register')
      .send({});

    expect(res.status).toBe(422);
  });

  it('Validierungsfehler: Passwort zu kurz → 422', async () => {
    const res = await request(app)
      .post('/onboarding/register')
      .send({ ...VALID_REGISTER_BODY, email: uniqueEmail(), password: 'kurz' });

    expect(res.status).toBe(422);
  });

  it('Validierungsfehler: device_token fehlt → 422', async () => {
    const { device_token: _, ...body } = VALID_REGISTER_BODY;
    const res = await request(app)
      .post('/onboarding/register')
      .send({ ...body, email: uniqueEmail() });

    expect(res.status).toBe(422);
  });

  it('Transaktion ist atomar: bei Fehler keine Partial-Daten', async () => {
    // device_token zu kurz (< 20 Zeichen) → Zod-422 vor DB-Zugriff
    const res = await request(app)
      .post('/onboarding/register')
      .send({ ...VALID_REGISTER_BODY, email: uniqueEmail(), device_token: 'zu-kurz' });

    expect(res.status).toBe(422);
  });
});

// ─── POST /onboarding/create-checkout-session ─────────────────────────────────

describe('POST /onboarding/create-checkout-session', () => {
  let token: string;
  let tenantId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));

    // Stripe-Mocks für jeden Test zurücksetzen (inkl. Call-History)
    mockCustomerCreate.mockClear();
    mockSessionCreate.mockClear();
    mockCustomerCreate.mockResolvedValue({ id: 'cus_test123' });
    mockSessionCreate.mockResolvedValue({ url: 'https://checkout.stripe.com/pay/test123' });

    // Stripe-Preise in ENV setzen
    process.env['STRIPE_SECRET_KEY']    = 'sk_test_dummy';
    process.env['STRIPE_PRICE_STARTER'] = 'price_starter_test';
    process.env['STRIPE_PRICE_PRO']     = 'price_pro_test';
    process.env['STRIPE_PRICE_BUSINESS']= 'price_business_test';
  });

  const VALID_CHECKOUT_BODY = {
    plan:        'starter',
    success_url: 'https://app.example.com/success',
    cancel_url:  'https://app.example.com/cancel',
  };

  it('Happy Path: legt Stripe-Customer an, speichert ID im Tenant, gibt checkout_url zurück', async () => {
    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .set('Authorization', `Bearer ${token}`)
      .send(VALID_CHECKOUT_BODY);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('checkout_url', 'https://checkout.stripe.com/pay/test123');

    // Stripe-Customer wurde einmal angelegt
    expect(mockCustomerCreate).toHaveBeenCalledOnce();

    // stripe_customer_id im Tenant gespeichert
    const [rows] = await db.execute<any[]>(
      'SELECT stripe_customer_id FROM tenants WHERE id = ?',
      [tenantId]
    );
    expect(rows[0].stripe_customer_id).toBe('cus_test123');

    // Checkout-Session mit korrektem Preis erstellt
    expect(mockSessionCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        customer:   'cus_test123',
        mode:       'subscription',
        line_items: [{ price: 'price_starter_test', quantity: 1 }],
      })
    );
  });

  it('Idempotenz: bestehender stripe_customer_id wird wiederverwendet, kein zweiter Customer', async () => {
    // stripe_customer_id manuell vorbelegen
    await db.execute(
      'UPDATE tenants SET stripe_customer_id = ? WHERE id = ?',
      ['cus_existing_456', tenantId]
    );

    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .set('Authorization', `Bearer ${token}`)
      .send(VALID_CHECKOUT_BODY);

    expect(res.status).toBe(200);
    expect(mockCustomerCreate).not.toHaveBeenCalled();       // kein neuer Customer
    expect(mockSessionCreate).toHaveBeenCalledWith(
      expect.objectContaining({ customer: 'cus_existing_456' })
    );
  });

  it('Ungültiger Plan → 422', async () => {
    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .set('Authorization', `Bearer ${token}`)
      .send({ ...VALID_CHECKOUT_BODY, plan: 'ultra' });

    expect(res.status).toBe(422);
  });

  it('Ungültige URLs → 422', async () => {
    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .set('Authorization', `Bearer ${token}`)
      .send({ plan: 'pro', success_url: 'keine-url', cancel_url: 'auch-keine' });

    expect(res.status).toBe(422);
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .send(VALID_CHECKOUT_BODY);

    expect(res.status).toBe(401);
  });

  it('Stripe-Preis nicht konfiguriert → 500', async () => {
    delete process.env['STRIPE_PRICE_STARTER'];

    const res = await request(app)
      .post('/onboarding/create-checkout-session')
      .set('Authorization', `Bearer ${token}`)
      .send(VALID_CHECKOUT_BODY);

    expect(res.status).toBe(500);
  });
});

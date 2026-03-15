import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function setup(conn: any) {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, vat_id, tax_number, plan, subscription_status)
     VALUES ('Shishabar GmbH', 'Musterstr. 1, 10115 Berlin', 'DE123456789', '12/345/67890', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad 1', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const [s] = await conn.execute(
    `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, 10000, 'open')`,
    [tenantId, deviceId, userId]
  );
  const sessionId = s.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  const [p] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha Groß', 2500, '19', '19')`,
    [tenantId]
  );
  const productId = p.insertId as number;

  return { tenantId, userId, deviceId, sessionId, token, productId };
}

/** Erstellt eine bezahlte Order und gibt receiptId zurück. */
async function setupPaidOrder(token: string, productId: number): Promise<number> {
  const orderRes = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
  const orderId = orderRes.body.id as number;

  await request(app)
    .post(`/orders/${orderId}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId, quantity: 1 });

  const payRes = await request(app)
    .post(`/orders/${orderId}/pay`)
    .set('Authorization', `Bearer ${token}`)
    .send({ method: 'cash', amount_cents: 2500 });

  return payRes.body.receipt_id as number;
}

// ─── GET /receipts/:id ────────────────────────────────────────────────────────

describe('GET /receipts/:id', () => {
  let token: string; let productId: number;

  beforeEach(async () => { ({ token, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Bon mit Pflichtfeldern zurück', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .get(`/receipts/${receiptId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.receipt_number).toBe(1);
    expect(res.body.status).toBe('active');
    expect(res.body.total_gross_cents).toBe(2500);
    expect(res.body.device_name).toBe('iPad 1');
    expect(res.body.tse_pending).toBe(true);
  });

  it('enthält raw_receipt_json mit Bon-Pflichtfeldern', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .get(`/receipts/${receiptId}`)
      .set('Authorization', `Bearer ${token}`);

    const json = res.body.raw_receipt_json;
    expect(json).toBeDefined();
    expect(json.tenant.name).toBe('Shishabar GmbH');
    expect(json.tenant.address).toBe('Musterstr. 1, 10115 Berlin');
    expect(json.tenant.vat_id).toBe('DE123456789');
    expect(json.tenant.tax_number).toBe('12/345/67890');
    expect(json.items.length).toBe(1);
    expect(json.items[0].product_name).toBe('Shisha Groß');
    expect(json.receipt_number).toBe(1);
  });

  it('enthält payments-Array', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .get(`/receipts/${receiptId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.body.payments.length).toBe(1);
    expect(res.body.payments[0].method).toBe('cash');
    expect(res.body.payments[0].amount_cents).toBe(2500);
  });

  it('enthält MwSt-Aufschlüsselung', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .get(`/receipts/${receiptId}`)
      .set('Authorization', `Bearer ${token}`);

    // 2500 brutto @ 19%: netto=2101, steuer=399
    expect(res.body.vat_19_net_cents).toBe(2101);
    expect(res.body.vat_19_tax_cents).toBe(399);
    expect(res.body.vat_19_net_cents + res.body.vat_19_tax_cents).toBe(2500);
  });

  it('404 bei nicht vorhandenem Bon', async () => {
    const res = await request(app)
      .get('/receipts/999999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('Tenant-Isolation: kann Bon eines anderen Tenants nicht lesen', async () => {
    // Tenant B + Receipt direkt in DB anlegen (kein API-Roundtrip nötig)
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de','x','owner')`, [t2.insertId]) as any;
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+','x')`, [t2.insertId]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`, [t2.insertId, d2.insertId, u2.insertId]) as any;
    const [o2] = await db.execute(`INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`, [t2.insertId, s2.insertId, u2.insertId]) as any;
    const [r2] = await db.execute(
      `INSERT INTO receipts (tenant_id, order_id, session_id, receipt_number, status, device_id, device_name, total_gross_cents, tse_pending)
       VALUES (?,?,?,1,'active',?,'+',1000,TRUE)`,
      [t2.insertId, o2.insertId, s2.insertId, d2.insertId]
    ) as any;

    const res = await request(app)
      .get(`/receipts/${r2.insertId}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

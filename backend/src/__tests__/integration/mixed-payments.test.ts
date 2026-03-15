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

  await conn.execute(
    `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, 10000, 'open')`,
    [tenantId, deviceId, userId]
  );

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  const [p] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha Groß', 3000, '19', '19')`,
    [tenantId]
  );
  const productId = p.insertId as number;

  return { tenantId, userId, deviceId, token, productId };
}

async function createOpenOrder(token: string, productId: number): Promise<number> {
  const orderRes = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
  const orderId = orderRes.body.id as number;
  await request(app)
    .post(`/orders/${orderId}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId, quantity: 1 });
  return orderId;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('POST /orders/:id/pay — gemischte Zahlung', () => {
  let token: string; let productId: number;

  beforeEach(async () => { ({ token, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('akzeptiert altes Einzel-Format (backwards compat)', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 3000 });

    expect(res.status).toBe(201);
    expect(res.body.total_gross_cents).toBe(3000);
    expect(res.body.payments).toHaveLength(1);
    expect(res.body.payments[0].method).toBe('cash');
    expect(res.body.payments[0].amount_cents).toBe(3000);
  });

  it('akzeptiert neues payments-Array-Format', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ payments: [{ method: 'cash', amount_cents: 3000 }] });

    expect(res.status).toBe(201);
    expect(res.body.payments).toHaveLength(1);
  });

  it('gemischte Zahlung: Bar + Karte', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        payments: [
          { method: 'cash', amount_cents: 1000 },
          { method: 'card', amount_cents: 2000 },
        ],
      });

    expect(res.status).toBe(201);
    expect(res.body.total_gross_cents).toBe(3000);
    expect(res.body.payments).toHaveLength(2);

    // Beide payments-Einträge in DB vorhanden
    const [rows] = await db.execute(
      `SELECT method, amount_cents FROM payments WHERE receipt_id = ? ORDER BY method`,
      [res.body.receipt_id]
    ) as any;
    expect(rows).toHaveLength(2);
    expect(rows.find((r: any) => r.method === 'card').amount_cents).toBe(2000);
    expect(rows.find((r: any) => r.method === 'cash').amount_cents).toBe(1000);
  });

  it('raw_receipt_json enthält payments-Array', async () => {
    const orderId = await createOpenOrder(token, productId);
    const payRes = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        payments: [
          { method: 'cash', amount_cents: 500 },
          { method: 'card', amount_cents: 2500 },
        ],
      });

    const receiptRes = await request(app)
      .get(`/receipts/${payRes.body.receipt_id}`)
      .set('Authorization', `Bearer ${token}`);

    const json = receiptRes.body.raw_receipt_json;
    expect(json.payments).toHaveLength(2);
    expect(json.payments.find((p: any) => p.method === 'cash').amount_cents).toBe(500);
    expect(json.payments.find((p: any) => p.method === 'card').amount_cents).toBe(2500);
  });

  it('422 wenn Summe der payments nicht dem Order-Total entspricht', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        payments: [
          { method: 'cash', amount_cents: 1000 },
          { method: 'card', amount_cents: 500 },  // Summe 1500 ≠ 3000
        ],
      });

    expect(res.status).toBe(422);
    expect(res.body.expected_cents).toBe(3000);
  });

  it('422 bei leerem payments-Array', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ payments: [] });

    expect(res.status).toBe(422);
  });

  it('422 bei fehlendem Body', async () => {
    const orderId = await createOpenOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({});

    expect(res.status).toBe(422);
  });
});

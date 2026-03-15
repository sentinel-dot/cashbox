import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function setup(conn: any, role: 'owner' | 'manager' | 'staff' = 'owner') {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, vat_id, tax_number, plan, subscription_status)
     VALUES ('Shishabar GmbH', 'Musterstr. 1, 10115 Berlin', 'DE123456789', '12/345/67890', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, ?)`,
    [tenantId, hash, role]
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
    { userId, tenantId, deviceId, role } as AuthPayload,
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

// ─── POST /receipts/:id/cancel ────────────────────────────────────────────────

describe('POST /receipts/:id/cancel', () => {
  let token: string; let productId: number; let tenantId: number;

  beforeEach(async () => { ({ token, productId, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('storniert einen aktiven Bon und erstellt Storno-Bon', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Kunde hat Bestellung storniert' });

    expect(res.status).toBe(201);
    expect(res.body.original_receipt_id).toBe(receiptId);
    expect(res.body.cancellation_receipt_id).toBeGreaterThan(receiptId);
    expect(res.body.cancellation_receipt_number).toBe(2); // receipt 1 = original
    expect(res.body.total_gross_cents).toBe(2500);
    expect(res.body.tse_pending).toBe(true); // kein TSS konfiguriert in Tests
  });

  it('Storno-Bon hat korrekte raw_receipt_json', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const cancelRes = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Testgrund' });

    const cancelReceiptId = cancelRes.body.cancellation_receipt_id as number;
    const res = await request(app)
      .get(`/receipts/${cancelReceiptId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    const json = res.body.raw_receipt_json;
    expect(json.cancellation).toBe(true);
    expect(json.original_receipt_number).toBe(1);
    expect(json.reason).toBe('Testgrund');
    expect(json.tenant.name).toBe('Shishabar GmbH');
    expect(json.items.length).toBe(1);
  });

  it('legt cancellations-Eintrag an (GoBD: Gegenbuchung)', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Test' });

    const [rows] = await db.execute(
      `SELECT * FROM cancellations WHERE original_receipt_id = ?`, [receiptId]
    ) as any;
    expect(rows.length).toBe(1);
    expect(rows[0].reason).toBe('Test');
    expect(rows[0].original_receipt_number).toBe(1);
  });

  it('409 bei Doppel-Storno', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Erster Storno' });

    const res = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Zweiter Storno' });

    expect(res.status).toBe(409);
  });

  it('403 für staff-Benutzer', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const { token: staffToken } = await setup(db, 'staff');
    const res = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ reason: 'Hack' });
    expect(res.status).toBe(403);
  });

  it('404 bei nicht vorhandenem Bon', async () => {
    const res = await request(app)
      .post('/receipts/999999/cancel')
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Test' });
    expect(res.status).toBe(404);
  });

  it('422 bei fehlendem reason', async () => {
    const receiptId = await setupPaidOrder(token, productId);
    const res = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann Bon eines anderen Tenants nicht stornieren', async () => {
    // Tenant B direkt in DB anlegen
    const [t2] = await db.execute(
      `INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`
    ) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const [u2] = await db.execute(
      `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'B','b@b.de','x','owner')`,
      [t2.insertId]
    ) as any;
    const [d2] = await db.execute(
      `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+','xx')`, [t2.insertId]
    ) as any;
    const [s2] = await db.execute(
      `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`,
      [t2.insertId, d2.insertId, u2.insertId]
    ) as any;
    const [o2] = await db.execute(
      `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`,
      [t2.insertId, s2.insertId, u2.insertId]
    ) as any;
    const [r2] = await db.execute(
      `INSERT INTO receipts (tenant_id, order_id, session_id, receipt_number, status, device_id, device_name, total_gross_cents, tse_pending)
       VALUES (?,?,?,1,'active',?,'+',1000,TRUE)`,
      [t2.insertId, o2.insertId, s2.insertId, d2.insertId]
    ) as any;

    const res = await request(app)
      .post(`/receipts/${r2.insertId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Isolation Test' });

    expect(res.status).toBe(404);
  });
});

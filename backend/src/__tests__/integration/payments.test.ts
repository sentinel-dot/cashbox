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

/** Erstellt eine offene Order mit einem Item und gibt orderId + totalCents zurück. */
async function setupOrder(token: string, productId: number, quantity = 1) {
  const orderRes = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
  const orderId = orderRes.body.id as number;

  const itemRes = await request(app)
    .post(`/orders/${orderId}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId, quantity });

  return { orderId, totalCents: itemRes.body.subtotal_cents as number };
}

// ─── POST /orders/:id/pay ─────────────────────────────────────────────────────

describe('POST /orders/:id/pay', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('zahlt Bestellung bar und erzeugt Receipt + Payment', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId, 1);
    // 2500 Cent für 1× Shisha

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: totalCents });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('receipt_id');
    expect(res.body).toHaveProperty('receipt_number');
    expect(res.body.receipt_number).toBe(1);  // erste Bon-Nummer
    expect(res.body.total_gross_cents).toBe(2500);
    expect(res.body.payments[0].method).toBe('cash');
    expect(res.body.tse_pending).toBe(true);
  });

  it('Bon-Nummer ist fortlaufend (zweite Zahlung = 2)', async () => {
    const { orderId: o1, totalCents: t1 } = await setupOrder(token, productId);
    const { orderId: o2, totalCents: t2 } = await setupOrder(token, productId);

    await request(app).post(`/orders/${o1}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'cash', amount_cents: t1 });
    const res2 = await request(app).post(`/orders/${o2}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'card', amount_cents: t2 });

    expect(res2.body.receipt_number).toBe(2);
  });

  it('MwSt-Aufschlüsselung ist korrekt (19%)', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId, 1);
    // 2500 Cent brutto bei 19%: netto = round(2500 * 100 / 119) = 2101, steuer = 399

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: totalCents });

    expect(res.body.vat_19_net_cents).toBe(2101);
    expect(res.body.vat_19_tax_cents).toBe(399);
    expect(res.body.vat_7_net_cents).toBe(0);
    expect(res.body.vat_7_tax_cents).toBe(0);
    // Invariante: netto + steuer = brutto
    expect(res.body.vat_19_net_cents + res.body.vat_19_tax_cents).toBe(2500);
  });

  it('Order-Status ist nach Zahlung "paid"', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    await request(app).post(`/orders/${orderId}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'cash', amount_cents: totalCents });

    const [rows] = await db.execute(`SELECT status, closed_at FROM orders WHERE id = ?`, [orderId]) as any;
    expect(rows[0].status).toBe('paid');
    expect(rows[0].closed_at).not.toBeNull();
  });

  it('Receipt wird in DB mit status="active" und raw_receipt_json gespeichert', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    const res = await request(app).post(`/orders/${orderId}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'cash', amount_cents: totalCents });

    const [rows] = await db.execute(`SELECT status, raw_receipt_json, device_name FROM receipts WHERE id = ?`, [res.body.receipt_id]) as any;
    expect(rows[0].status).toBe('active');
    expect(rows[0].device_name).toBe('iPad 1');

    const json = typeof rows[0].raw_receipt_json === 'string'
      ? JSON.parse(rows[0].raw_receipt_json)
      : rows[0].raw_receipt_json;
    expect(json).toHaveProperty('receipt_number', 1);
    expect(json.tenant.name).toBe('Shishabar GmbH');
    expect(json.tenant.vat_id).toBe('DE123456789');
    expect(json.items.length).toBe(1);
    expect(json.items[0].product_name).toBe('Shisha Groß');
  });

  it('Payment-Eintrag in DB vorhanden', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    const res = await request(app).post(`/orders/${orderId}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'card', amount_cents: totalCents });

    const [rows] = await db.execute(`SELECT method, amount_cents FROM payments WHERE receipt_id = ?`, [res.body.receipt_id]) as any;
    expect(rows.length).toBe(1);
    expect(rows[0].method).toBe('card');
    expect(rows[0].amount_cents).toBe(totalCents);
  });

  it('receipt_sequences wird korrekt inkrementiert', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    await request(app).post(`/orders/${orderId}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'cash', amount_cents: totalCents });

    const [rows] = await db.execute(`SELECT last_number FROM receipt_sequences WHERE tenant_id = ?`, [tenantId]) as any;
    expect(rows[0].last_number).toBe(1);
  });

  it('422 wenn amount_cents nicht mit Order-Total übereinstimmt', async () => {
    const { orderId } = await setupOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 1 });
    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('expected_cents');
  });

  it('422 wenn Order keine Items hat', async () => {
    const orderRes = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
    const orderId = orderRes.body.id as number;

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 1 });
    expect(res.status).toBe(422);
  });

  it('409 wenn Order bereits bezahlt', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    await request(app).post(`/orders/${orderId}/pay`).set('Authorization', `Bearer ${token}`).send({ method: 'cash', amount_cents: totalCents });

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: totalCents });
    expect(res.status).toBe(409);
  });

  it('422 bei ungültiger Zahlungsart', async () => {
    const { orderId, totalCents } = await setupOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'crypto', amount_cents: totalCents });
    expect(res.status).toBe(422);
  });

  it('422 bei float amount_cents', async () => {
    const { orderId } = await setupOrder(token, productId);
    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 25.00 });
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann Order eines anderen Tenants nicht bezahlen', async () => {
    // Tenant B komplett aufsetzen
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de',?,'owner')`, [t2.insertId, hash]) as any;
    const th = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+',?)`, [t2.insertId, th]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`, [t2.insertId, d2.insertId, u2.insertId]) as any;
    const [p2] = await db.execute(`INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?,'FP',1000,'19','19')`, [t2.insertId]) as any;
    const tok2 = jwt.sign({ userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload, process.env['JWT_SECRET'] ?? 'test-secret', { expiresIn: '15m' });

    // Tenant B erstellt Order
    const { orderId: orderId2, totalCents: total2 } = await setupOrder(tok2, p2.insertId);

    // Tenant A versucht Tenant B's Order zu bezahlen
    const res = await request(app)
      .post(`/orders/${orderId2}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: total2 });
    expect(res.status).toBe(404);
  });
});

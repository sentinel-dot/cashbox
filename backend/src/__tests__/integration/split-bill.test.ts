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

  // Zwei verschiedene Produkte für Split-Szenarien
  const [p1] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha Groß', 2500, '19', '19')`,
    [tenantId]
  );
  const [p2] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Limo', 400, '19', '19')`,
    [tenantId]
  );

  return { tenantId, userId, deviceId, token, productId1: p1.insertId as number, productId2: p2.insertId as number };
}

/** Erstellt eine Order mit 2 Items (p1 + p2) und gibt orderId + itemIds zurück. */
async function setupOrderWithTwoItems(token: string, productId1: number, productId2: number) {
  const orderRes = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
  const orderId = orderRes.body.id as number;

  const item1Res = await request(app)
    .post(`/orders/${orderId}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId1, quantity: 1 });

  const item2Res = await request(app)
    .post(`/orders/${orderId}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId2, quantity: 1 });

  return {
    orderId,
    itemId1:  item1Res.body.id as number,
    itemId2:  item2Res.body.id as number,
    total1:   item1Res.body.subtotal_cents as number,  // 2500
    total2:   item2Res.body.subtotal_cents as number,  // 400
  };
}

// ─── POST /orders/:id/pay/split ───────────────────────────────────────────────

describe('POST /orders/:id/pay/split', () => {
  let token: string; let productId1: number; let productId2: number;

  beforeEach(async () => { ({ token, productId1, productId2 } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('Happy Path: 2 Splits mit je einem Item und korrekter Zahlung', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'card', amount_cents: total2 }] },
        ],
      });

    expect(res.status).toBe(201);
    expect(res.body.receipts).toHaveLength(2);
    expect(res.body.receipts[0].split_index).toBe(1);
    expect(res.body.receipts[1].split_index).toBe(2);
    expect(res.body.receipts[0].total_gross_cents).toBe(total1);
    expect(res.body.receipts[1].total_gross_cents).toBe(total2);
  });

  it('erzeugt fortlaufende Bon-Nummern pro Split', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    expect(res.body.receipts[0].receipt_number).toBe(1);
    expect(res.body.receipts[1].receipt_number).toBe(2);
  });

  it('beide Receipts haben is_split_receipt=true und gleiche split_group_id', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    const [rows] = await db.execute(
      `SELECT is_split_receipt, split_group_id FROM receipts
       WHERE id IN (?, ?) ORDER BY id`,
      [res.body.receipts[0].receipt_id, res.body.receipts[1].receipt_id]
    ) as any;

    expect(rows[0].is_split_receipt).toBe(1);
    expect(rows[1].is_split_receipt).toBe(1);
    expect(rows[0].split_group_id).toBe(rows[1].split_group_id);
  });

  it('raw_receipt_json jedes Splits enthält nur die zugehörigen Items', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const payRes = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    const r1 = await request(app)
      .get(`/receipts/${payRes.body.receipts[0].receipt_id}`)
      .set('Authorization', `Bearer ${token}`);
    const r2 = await request(app)
      .get(`/receipts/${payRes.body.receipts[1].receipt_id}`)
      .set('Authorization', `Bearer ${token}`);

    expect(r1.body.raw_receipt_json.items).toHaveLength(1);
    expect(r1.body.raw_receipt_json.items[0].product_name).toBe('Shisha Groß');
    expect(r2.body.raw_receipt_json.items).toHaveLength(1);
    expect(r2.body.raw_receipt_json.items[0].product_name).toBe('Limo');
  });

  it('Order ist danach paid', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    const [rows] = await db.execute(`SELECT status FROM orders WHERE id = ?`, [orderId]) as any;
    expect(rows[0].status).toBe('paid');
  });

  it('422 bei überschneidenden Item-IDs', async () => {
    const { orderId, itemId1, total1 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
        ],
      });

    expect(res.status).toBe(422);
  });

  it('422 wenn nicht alle Items abgedeckt sind', async () => {
    const { orderId, itemId1, total1 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          // itemId2 fehlt
        ],
      });

    expect(res.status).toBe(422);
  });

  it('422 wenn Zahlungssumme eines Splits nicht stimmt', async () => {
    const { orderId, itemId1, itemId2, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: 1 }] }, // falsch
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    expect(res.status).toBe(422);
    expect(res.body.expected_cents).toBe(2500);
  });

  it('422 bei leerem splits-Array', async () => {
    const { orderId } = await setupOrderWithTwoItems(token, productId1, productId2);
    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({ splits: [] });
    expect(res.status).toBe(422);
  });

  it('409 bei bereits bezahlter Order', async () => {
    const { orderId, itemId1, itemId2, total1, total2 } = await setupOrderWithTwoItems(token, productId1, productId2);

    // Erst normal bezahlen
    await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: total1 + total2 });

    // Dann Split versuchen
    const res = await request(app)
      .post(`/orders/${orderId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [itemId1], payments: [{ method: 'cash', amount_cents: total1 }] },
          { order_item_ids: [itemId2], payments: [{ method: 'cash', amount_cents: total2 }] },
        ],
      });

    expect(res.status).toBe(409);
  });

  it('Tenant-Isolation: kann Order eines anderen Tenants nicht splitten', async () => {
    // Tenant B direkt in DB
    const [t2] = await db.execute(
      `INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`
    ) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const [u2] = await db.execute(
      `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'B','b@b.de','x','owner')`,
      [t2.insertId]
    ) as any;
    const [d2] = await db.execute(
      `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+','xy')`, [t2.insertId]
    ) as any;
    const [s2] = await db.execute(
      `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`,
      [t2.insertId, d2.insertId, u2.insertId]
    ) as any;
    const [o2] = await db.execute(
      `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`,
      [t2.insertId, s2.insertId, u2.insertId]
    ) as any;

    const res = await request(app)
      .post(`/orders/${o2.insertId}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [{ order_item_ids: [999], payments: [{ method: 'cash', amount_cents: 100 }] }],
      });

    expect(res.status).toBe(404);
  });
});

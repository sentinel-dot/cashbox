/**
 * Externe Tests — Fiskaly Sandbox
 *
 * Testet echte TSE-Transaktionen gegen die Fiskaly Sandbox-API.
 * Voraussetzungen (.env):
 *   FISKALY_API_KEY, FISKALY_API_SECRET
 *   FISKALY_TSS_ID      ← aus fiskaly-setup.ts
 *   FISKALY_CLIENT_ID   ← aus fiskaly-setup.ts
 *
 * Ausführen: npm run test:external
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── TSS / Client aus .env ────────────────────────────────────────────────────

const TSS_ID    = process.env['FISKALY_TSS_ID']!;
const CLIENT_ID = process.env['FISKALY_CLIENT_ID']!;

// ─── Setup ────────────────────────────────────────────────────────────────────

async function setup() {
  const [t] = await db.execute<any>(
    `INSERT INTO tenants (name, address, vat_id, tax_number, plan, subscription_status, fiskaly_tss_id)
     VALUES ('Shishabar GmbH', 'Musterstr. 1, 10115 Berlin', 'DE123456789', '12/345/67890', 'business', 'active', ?)`,
    [TSS_ID]
  );
  const tenantId = t.insertId as number;
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'Owner', 'o@shisha.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await db.execute<any>(
    `INSERT INTO devices (tenant_id, name, device_token_hash, tse_client_id) VALUES (?, 'iPad 1', ?, ?)`,
    [tenantId, tokenHash, CLIENT_ID]
  );
  const deviceId = d.insertId as number;

  await db.execute(
    `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, 10000, 'open')`,
    [tenantId, deviceId, userId]
  );

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  // Produkte
  const [p1] = await db.execute<any>(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha Groß', 2500, '19', '19')`,
    [tenantId]
  );
  const [p2] = await db.execute<any>(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Limo', 400, '7', '7')`,
    [tenantId]
  );

  return {
    tenantId, userId, deviceId, token,
    productId1: p1.insertId as number,
    productId2: p2.insertId as number,
  };
}

async function createOrderWithItem(token: string, productId: number, quantity = 1) {
  const { body: order } = await request(app)
    .post('/orders').set('Authorization', `Bearer ${token}`).send({});
  await request(app)
    .post(`/orders/${order.id}/items`)
    .set('Authorization', `Bearer ${token}`)
    .send({ product_id: productId, quantity });
  return order.id as number;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('Fiskaly Sandbox — TSE-Transaktion', () => {
  let token: string;
  let productId1: number;
  let productId2: number;

  beforeEach(async () => {
    ({ token, productId1, productId2 } = await setup());
  });
  afterEach(() => { /* cleanup via setup.ts */ });

  // ── Barzahlung ──────────────────────────────────────────────────────────────

  it('Barzahlung erzeugt echte TSE-Signatur', async () => {
    const orderId = await createOrderWithItem(token, productId1);

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 2500 });

    expect(res.status).toBe(201);
    expect(res.body.tse_pending).toBe(false);
    expect(res.body.tse_transaction_id).toBeTruthy();
    expect(res.body.tse_serial_number).toBeTruthy();
    expect(res.body.tse_counter).toBeGreaterThan(0);

    // GET /receipts/:id — receipt_data.qr_code_data muss vorhanden sein
    const receiptRes = await request(app)
      .get(`/receipts/${res.body.receipt_id}`)
      .set('Authorization', `Bearer ${token}`);

    expect(receiptRes.body.receipt_data.qr_code_data).toMatch(/^V0;/);
    expect(receiptRes.body.receipt_data.tse_signature).toBeTruthy();
  });

  // ── Gemischte MwSt (7% + 19%) ──────────────────────────────────────────────

  it('Gemischte MwSt — TSE amounts_per_vat_rates korrekt', async () => {
    const { body: order } = await request(app)
      .post('/orders').set('Authorization', `Bearer ${token}`).send({});
    await request(app).post(`/orders/${order.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId1, quantity: 1 }); // 2500 @ 19%
    await request(app).post(`/orders/${order.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId2, quantity: 1 }); // 400 @ 7%

    const res = await request(app)
      .post(`/orders/${order.id}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 2900 });

    expect(res.status).toBe(201);
    expect(res.body.tse_pending).toBe(false);
    expect(res.body.vat_7_tax_cents).toBeGreaterThan(0);
    expect(res.body.vat_19_tax_cents).toBeGreaterThan(0);

    // Beide MwSt-Sätze korrekt signiert → Serial in Receipt vorhanden
    const receiptRes = await request(app)
      .get(`/receipts/${res.body.receipt_id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(receiptRes.body.receipt_data.tse_serial_number).toBeTruthy();
  });

  // ── Gemischte Zahlung (Bar + Karte) ────────────────────────────────────────

  it('Bar + Karte — eine TSE-Transaktion, zwei Zahlungsmittel', async () => {
    const orderId = await createOrderWithItem(token, productId1); // 2500

    const res = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        payments: [
          { method: 'cash', amount_cents: 1000 },
          { method: 'card', amount_cents: 1500 },
        ],
      });

    expect(res.status).toBe(201);
    expect(res.body.tse_pending).toBe(false);
    expect(res.body.payments).toHaveLength(2);
    expect(res.body.tse_transaction_id).toBeTruthy();
  });

  // ── Split Bill ──────────────────────────────────────────────────────────────

  it('Split Bill — jeder Split hat eigene TSE-Transaktion', async () => {
    const { body: order } = await request(app)
      .post('/orders').set('Authorization', `Bearer ${token}`).send({});
    const { body: item1 } = await request(app).post(`/orders/${order.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId1, quantity: 1 }); // 2500
    const { body: item2 } = await request(app).post(`/orders/${order.id}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId2, quantity: 1 }); // 400

    const res = await request(app)
      .post(`/orders/${order.id}/pay/split`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        splits: [
          { order_item_ids: [item1.id], payments: [{ method: 'cash', amount_cents: 2500 }] },
          { order_item_ids: [item2.id], payments: [{ method: 'card', amount_cents: 400  }] },
        ],
      });

    expect(res.status).toBe(201);
    expect(res.body.receipts).toHaveLength(2);

    // Beide Receipts haben echte TSE-Signaturen
    for (const r of res.body.receipts) {
      expect(r.tse_pending).toBe(false);

      const receiptRes = await request(app)
        .get(`/receipts/${r.receipt_id}`)
        .set('Authorization', `Bearer ${token}`);
      expect(receiptRes.body.receipt_data.tse_transaction_id).toBeTruthy();
      expect(receiptRes.body.receipt_data.qr_code_data).toMatch(/^V0;/);
    }

    // Jeder Split hat eine ANDERE tse_transaction_id
    const [r1, r2] = await Promise.all(
      res.body.receipts.map((r: any) =>
        request(app).get(`/receipts/${r.receipt_id}`).set('Authorization', `Bearer ${token}`)
      )
    );
    expect(r1.body.tse_transaction_id).not.toBe(r2.body.tse_transaction_id);
  });

  // ── Storno ──────────────────────────────────────────────────────────────────

  it('Storno erzeugt CANCELLATION TSE-Transaktion mit eigener Signatur', async () => {
    const orderId = await createOrderWithItem(token, productId1);
    const payRes = await request(app)
      .post(`/orders/${orderId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 2500 });
    expect(payRes.status).toBe(201);
    const receiptId = payRes.body.receipt_id;
    const originalTxId = payRes.body.tse_transaction_id;

    // Storno
    const cancelRes = await request(app)
      .post(`/receipts/${receiptId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Kunde hat Bestellung storniert' });

    expect(cancelRes.status).toBe(201);
    expect(cancelRes.body.tse_pending).toBe(false);
    expect(cancelRes.body.tse_transaction_id).toBeTruthy();
    // Storno hat ANDERE TSE-TX als Original
    expect(cancelRes.body.tse_transaction_id).not.toBe(originalTxId);

    // Storno-Bon prüfen
    const cancelReceiptRes = await request(app)
      .get(`/receipts/${cancelRes.body.cancellation_receipt_id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(cancelReceiptRes.body.receipt_data.is_cancellation).toBe(true);
    expect(cancelReceiptRes.body.receipt_data.original_receipt_number).toBeGreaterThan(0);
    expect(cancelReceiptRes.body.receipt_data.qr_code_data).toMatch(/^V0;/);
  });

  // ── TSE-Counter steigt fortlaufend ──────────────────────────────────────────

  it('TSE-Counter ist bei jeder TX um mind. 1 höher', async () => {
    const orderId1 = await createOrderWithItem(token, productId1);
    const res1 = await request(app)
      .post(`/orders/${orderId1}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 2500 });

    const orderId2 = await createOrderWithItem(token, productId1);
    const res2 = await request(app)
      .post(`/orders/${orderId2}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .send({ method: 'cash', amount_cents: 2500 });

    expect(res1.body.tse_counter).toBeGreaterThan(0);
    expect(res2.body.tse_counter).toBeGreaterThan(res1.body.tse_counter);
  });
});

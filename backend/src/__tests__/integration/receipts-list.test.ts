import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function setup(plan: 'starter' | 'pro' | 'business' = 'business') {
  const [t] = await db.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Test GmbH', 'Str. 1, Berlin', ?, 'active')`,
    [plan]
  ) as any;
  const tenantId = t.insertId as number;
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, 'owner')`,
    [tenantId, hash]
  ) as any;
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await db.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  ) as any;
  const deviceId = d.insertId as number;

  const [s] = await db.execute(
    `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, 5000, 'open')`,
    [tenantId, deviceId, userId]
  ) as any;
  const sessionId = s.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  return { tenantId, userId, deviceId, sessionId, token };
}

/** Fügt einen Receipt direkt in die DB ein (ohne API-Roundtrip). */
async function insertReceipt(tenantId: number, sessionId: number, deviceId: number, userId: number) {
  await db.execute(
    'UPDATE receipt_sequences SET last_number = last_number + 1 WHERE tenant_id = ?',
    [tenantId]
  );
  const [seq] = await db.execute<any[]>(
    'SELECT last_number FROM receipt_sequences WHERE tenant_id = ?',
    [tenantId]
  );
  const receiptNumber = seq[0].last_number;

  const [o] = await db.execute(
    `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway, status, closed_at)
     VALUES (?, ?, ?, FALSE, 'paid', NOW())`,
    [tenantId, sessionId, userId]
  ) as any;
  const orderId = o.insertId as number;

  const [r] = await db.execute(
    `INSERT INTO receipts
       (tenant_id, order_id, session_id, receipt_number, status,
        device_id, device_name, tse_pending,
        vat_7_net_cents, vat_7_tax_cents, vat_19_net_cents, vat_19_tax_cents,
        total_gross_cents, tip_cents)
     VALUES (?, ?, ?, ?, 'active', ?, 'iPad Test', TRUE, 0, 0, 2101, 399, 2500, 0)`,
    [tenantId, orderId, sessionId, receiptNumber, deviceId]
  ) as any;

  return { receiptId: r.insertId as number, orderId, receiptNumber };
}

// ─── GET /receipts ─────────────────────────────────────────────────────────────

describe('GET /receipts', () => {
  let token: string;
  let tenantId: number;
  let sessionId: number;
  let deviceId: number;
  let userId: number;

  beforeEach(async () => {
    ({ token, tenantId, sessionId, deviceId, userId } = await setup('business'));
  });

  it('gibt leere Liste zurück wenn keine Bons vorhanden', async () => {
    const res = await request(app).get('/receipts').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.receipts).toEqual([]);
    expect(res.body.total).toBe(0);
    expect(res.body.limit).toBe(50);
    expect(res.body.offset).toBe(0);
  });

  it('gibt vorhandene Bons zurück', async () => {
    await insertReceipt(tenantId, sessionId, deviceId, userId);
    await insertReceipt(tenantId, sessionId, deviceId, userId);

    const res = await request(app).get('/receipts').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(2);
    expect(res.body.receipts).toHaveLength(2);
    // Kein raw_receipt_json in der Liste
    expect(res.body.receipts[0]).not.toHaveProperty('raw_receipt_json');
    expect(res.body.receipts[0]).toHaveProperty('total_gross_cents');
    expect(res.body.receipts[0]).toHaveProperty('receipt_number');
  });

  it('filtert nach session_id', async () => {
    await insertReceipt(tenantId, sessionId, deviceId, userId);

    // Zweite Session anlegen
    const [s2] = await db.execute(
      `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
       VALUES (?, ?, ?, 5000, 'open')`,
      [tenantId, deviceId, userId]
    ) as any;
    await insertReceipt(tenantId, s2.insertId, deviceId, userId);

    const res = await request(app)
      .get(`/receipts?session_id=${sessionId}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(1);
    expect(res.body.receipts[0].session_id).toBe(sessionId);
  });

  it('paginiert korrekt (limit + offset)', async () => {
    await insertReceipt(tenantId, sessionId, deviceId, userId);
    await insertReceipt(tenantId, sessionId, deviceId, userId);
    await insertReceipt(tenantId, sessionId, deviceId, userId);

    const res = await request(app)
      .get('/receipts?limit=2&offset=1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(3);   // Gesamtanzahl korrekt
    expect(res.body.receipts).toHaveLength(2); // nur 2 zurückgegeben
    expect(res.body.limit).toBe(2);
    expect(res.body.offset).toBe(1);
  });

  it('422 bei ungültigem Datumsformat', async () => {
    const res = await request(app)
      .get('/receipts?from=15-03-2026')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('error');
  });

  it('422 bei limit außerhalb des erlaubten Bereichs', async () => {
    const res = await request(app)
      .get('/receipts?limit=200')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
  });

  it('403 wenn Starter-Plan zu weit in die Vergangenheit schaut', async () => {
    const { token: starterToken } = await setup('starter');
    // Datum von vor 60 Tagen (außerhalb der 30-Tage-Grenze)
    const longAgo = new Date();
    longAgo.setDate(longAgo.getDate() - 60);
    const fromDate = longAgo.toISOString().slice(0, 10);

    const res = await request(app)
      .get(`/receipts?from=${fromDate}`)
      .set('Authorization', `Bearer ${starterToken}`);
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Plan-Limit/);
  });

  it('Tenant-Isolation: Tenant B sieht keine Bons von Tenant A', async () => {
    // Bon für Tenant A anlegen
    await insertReceipt(tenantId, sessionId, deviceId, userId);

    // Tenant B komplett aufsetzen
    const { token: tokenB } = await setup('business');

    const res = await request(app).get('/receipts').set('Authorization', `Bearer ${tokenB}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
    expect(res.body.receipts).toHaveLength(0);
  });
});

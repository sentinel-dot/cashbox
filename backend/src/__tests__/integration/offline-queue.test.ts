import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

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
     VALUES (?, 'Owner', 'o@t.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
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

  return { tenantId, userId, deviceId, sessionId, token };
}

/** Legt eine Order + optionalen Receipt + Queue-Eintrag an. */
async function seedQueueEntry(
  conn: any,
  tenantId: number,
  userId: number,
  deviceId: number,
  sessionId: number,
  idempotencyKey: string,
  withReceiptId = true
) {
  const [o] = await conn.execute(
    `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, status)
     VALUES (?, ?, ?, 'paid')`,
    [tenantId, sessionId, userId]
  ) as any;
  const orderId = o.insertId as number;

  let receiptId: number | null = null;
  if (withReceiptId) {
    const [r] = await conn.execute(
      `INSERT INTO receipts
         (tenant_id, order_id, session_id, receipt_number, status,
          device_id, device_name,
          vat_7_net_cents, vat_7_tax_cents, vat_19_net_cents, vat_19_tax_cents,
          total_gross_cents, tip_cents, is_takeaway, tse_pending)
       VALUES (?, ?, ?, 1, 'active', ?, 'iPad', 0, 0, 2101, 399, 2500, 0, 0, 1)`,
      [tenantId, orderId, sessionId, deviceId]
    ) as any;
    receiptId = r.insertId as number;
  }

  const payload = {
    vat7GrossCents:  0,
    vat19GrossCents: 2500,
    payments:        [{ method: 'cash', amount_cents: 2500 }],
    receipt_id:      receiptId,
  };

  await conn.execute(
    `INSERT INTO offline_queue (tenant_id, device_id, order_id, payload_json, idempotency_key, status)
     VALUES (?, ?, ?, ?, ?, 'pending')`,
    [tenantId, deviceId, orderId, JSON.stringify(payload), idempotencyKey]
  );

  return { orderId, receiptId };
}

// ─── GET /sync/offline-queue ─────────────────────────────────────────────────

describe('GET /sync/offline-queue', () => {
  let token: string;
  let tenantId: number;
  let userId: number;
  let deviceId: number;
  let sessionId: number;

  beforeEach(async () => {
    ({ token, tenantId, userId, deviceId, sessionId } = await setup(db));
  });
  afterEach(() => { /* cleanup: global afterEach in setup.ts */ });

  it('gibt Status-Zusammenfassung zurück', async () => {
    await seedQueueEntry(db, tenantId, userId, deviceId, sessionId, uuidv4());

    const res = await request(app)
      .get('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.pending).toBe(1);
    expect(res.body.completed).toBe(0);
    expect(res.body.failed).toBe(0);
  });

  it('gibt 0 zurück wenn Queue leer', async () => {
    const res = await request(app)
      .get('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.pending).toBe(0);
  });

  it('Tenant-Isolation: sieht nur eigene Einträge', async () => {
    await seedQueueEntry(db, tenantId, userId, deviceId, sessionId, uuidv4());

    const { token: tokenB } = await setup(db);
    const res = await request(app)
      .get('/sync/offline-queue')
      .set('Authorization', `Bearer ${tokenB}`);

    expect(res.status).toBe(200);
    expect(res.body.pending).toBe(0);
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app).get('/sync/offline-queue');
    expect(res.status).toBe(401);
  });
});

// ─── POST /sync/offline-queue ─────────────────────────────────────────────────

describe('POST /sync/offline-queue', () => {
  let token: string;
  let tenantId: number;
  let userId: number;
  let deviceId: number;
  let sessionId: number;

  beforeEach(async () => {
    ({ token, tenantId, userId, deviceId, sessionId } = await setup(db));
  });
  afterEach(() => { /* cleanup: global afterEach in setup.ts */ });

  it('verarbeitet pending-Eintrag (kein TSE konfiguriert → failed)', async () => {
    const idempotencyKey = uuidv4();
    await seedQueueEntry(db, tenantId, userId, deviceId, sessionId, idempotencyKey);

    const res = await request(app)
      .post('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`)
      .send();

    expect(res.status).toBe(200);
    expect(res.body.processed).toBe(1);
    // Kein TSS konfiguriert → processTseTransaction gibt pending:true → failed
    expect(res.body.failed).toBe(1);
    expect(res.body.succeeded).toBe(0);

    const [rows] = await db.execute<any[]>(
      `SELECT status, retry_count FROM offline_queue
       WHERE idempotency_key = ? AND tenant_id = ?`,
      [idempotencyKey, tenantId]
    );
    expect(rows[0].status).toBe('failed');
    expect(rows[0].retry_count).toBe(1);
  });

  it('Eintrag ohne receipt_id wird als failed markiert', async () => {
    const idempotencyKey = uuidv4();
    await seedQueueEntry(db, tenantId, userId, deviceId, sessionId, idempotencyKey, false);

    const res = await request(app)
      .post('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`)
      .send();

    expect(res.status).toBe(200);
    expect(res.body.processed).toBe(1);
    expect(res.body.failed).toBe(1);

    const [rows] = await db.execute<any[]>(
      `SELECT status, error_message FROM offline_queue
       WHERE idempotency_key = ? AND tenant_id = ?`,
      [idempotencyKey, tenantId]
    );
    expect(rows[0].status).toBe('failed');
    expect(rows[0].error_message).toContain('receipt_id');
  });

  it('leere Queue: processed=0, pending_remaining=0', async () => {
    const res = await request(app)
      .post('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`)
      .send();

    expect(res.status).toBe(200);
    expect(res.body.processed).toBe(0);
    expect(res.body.pending_remaining).toBe(0);
  });

  it('Tenant-Isolation: verarbeitet keine Einträge anderer Tenants', async () => {
    const { tenantId: tenantIdA, userId: userIdA, deviceId: deviceIdA, sessionId: sessionIdA } = await setup(db);
    const idempotencyKey = uuidv4();
    await seedQueueEntry(db, tenantIdA, userIdA, deviceIdA, sessionIdA, idempotencyKey);

    // Tenant B ruft sync auf — sieht Tenant-A-Eintrag nicht
    const res = await request(app)
      .post('/sync/offline-queue')
      .set('Authorization', `Bearer ${token}`)
      .send();

    expect(res.status).toBe(200);
    expect(res.body.processed).toBe(0);

    // Tenant A's Eintrag bleibt unverändert
    const [rows] = await db.execute<any[]>(
      `SELECT status FROM offline_queue
       WHERE idempotency_key = ? AND tenant_id = ?`,
      [idempotencyKey, tenantIdA]
    );
    expect(rows[0].status).toBe('pending');
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app).post('/sync/offline-queue').send();
    expect(res.status).toBe(401);
  });
});

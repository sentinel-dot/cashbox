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

/** Legt eine bezahlte Order + Receipt direkt in der DB an. */
async function insertPaidReceipt(
  tenantId: number, sessionId: number, deviceId: number, userId: number,
  opts: { vat19GrossCents?: number; method?: 'cash' | 'card'; dateOverride?: string } = {}
) {
  const { vat19GrossCents = 2500, method = 'cash', dateOverride } = opts;

  await db.execute(
    'UPDATE receipt_sequences SET last_number = last_number + 1 WHERE tenant_id = ?',
    [tenantId]
  );
  const [seq] = await db.execute<any[]>(
    'SELECT last_number FROM receipt_sequences WHERE tenant_id = ?',
    [tenantId]
  );
  const receiptNumber = seq[0].last_number;

  const netCents = Math.round((vat19GrossCents * 100) / 119);
  const taxCents = vat19GrossCents - netCents;

  const closedAt = dateOverride ? `'${dateOverride} 12:00:00'` : 'NOW()';
  const [o] = await db.execute(
    `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway, status, closed_at)
     VALUES (?, ?, ?, FALSE, 'paid', ${closedAt})`,
    [tenantId, sessionId, userId]
  ) as any;
  const orderId = o.insertId as number;

  const createdAt = dateOverride ? `'${dateOverride} 12:00:00'` : 'NOW()';
  const [r] = await db.execute(
    `INSERT INTO receipts
       (tenant_id, order_id, session_id, receipt_number, status,
        device_id, device_name, tse_pending,
        vat_7_net_cents, vat_7_tax_cents,
        vat_19_net_cents, vat_19_tax_cents,
        total_gross_cents, tip_cents, created_at)
     VALUES (?, ?, ?, ?, 'active', ?, 'iPad', TRUE,
             0, 0, ?, ?, ?, 0, ${createdAt})`,
    [tenantId, orderId, sessionId, receiptNumber, deviceId, netCents, taxCents, vat19GrossCents]
  ) as any;
  const receiptId = r.insertId as number;

  await db.execute(
    `INSERT INTO payments (order_id, receipt_id, method, amount_cents, tip_cents, paid_by_user_id, paid_at)
     VALUES (?, ?, ?, ?, 0, ?, ${createdAt})`,
    [orderId, receiptId, method, vat19GrossCents, userId]
  );

  return { receiptId, orderId, receiptNumber };
}

const TODAY = new Date().toISOString().slice(0, 10);

// ─── GET /reports/daily ───────────────────────────────────────────────────────

describe('GET /reports/daily', () => {
  let token: string;
  let tenantId: number;
  let sessionId: number;
  let deviceId: number;
  let userId: number;

  beforeEach(async () => {
    ({ token, tenantId, sessionId, deviceId, userId } = await setup('business'));
  });

  it('gibt Nullwerte zurück wenn keine Bons vorhanden', async () => {
    const res = await request(app)
      .get(`/reports/daily?date=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.date).toBe(TODAY);
    expect(res.body.receipt_count).toBe(0);
    expect(res.body.total_gross_cents).toBe(0);
    expect(res.body.payments_cash_cents).toBe(0);
    expect(res.body.payments_card_cents).toBe(0);
    expect(res.body.sessions).toHaveLength(1); // offene Session des Tages
  });

  it('aggregiert Umsatz und MwSt korrekt', async () => {
    // 2× Bar, 1× Karte
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 2500, method: 'cash' });
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 1190, method: 'cash' });
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 3570, method: 'card' });

    const res = await request(app)
      .get(`/reports/daily?date=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.receipt_count).toBe(3);
    expect(res.body.total_gross_cents).toBe(2500 + 1190 + 3570);
    expect(res.body.payments_cash_cents).toBe(2500 + 1190);
    expect(res.body.payments_card_cents).toBe(3570);
    // MwSt-Summe: Netto + Steuer = Brutto
    expect(res.body.vat_19_net_cents + res.body.vat_19_tax_cents).toBe(2500 + 1190 + 3570);
    expect(res.body.vat_7_net_cents).toBe(0);
    expect(res.body.vat_7_tax_cents).toBe(0);
  });

  it('422 bei fehlendem date-Parameter', async () => {
    const res = await request(app).get('/reports/daily').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });

  it('422 bei ungültigem Datumsformat', async () => {
    const res = await request(app)
      .get('/reports/daily?date=15-03-2026')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
  });

  it('403 wenn Starter-Plan zu weit zurückschaut', async () => {
    const { token: starterToken } = await setup('starter');
    const old = new Date();
    old.setDate(old.getDate() - 60);
    const res = await request(app)
      .get(`/reports/daily?date=${old.toISOString().slice(0, 10)}`)
      .set('Authorization', `Bearer ${starterToken}`);
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Plan-Limit/);
  });

  it('Tenant-Isolation: Tenant B sieht nur eigene Daten', async () => {
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 5000 });

    const { token: tokenB } = await setup('business');
    const res = await request(app)
      .get(`/reports/daily?date=${TODAY}`)
      .set('Authorization', `Bearer ${tokenB}`);
    expect(res.status).toBe(200);
    // Tenant B hat keine eigenen Bons — Umsatz muss 0 sein
    expect(res.body.total_gross_cents).toBe(0);
    expect(res.body.receipt_count).toBe(0);
  });
});

// ─── GET /reports/summary ─────────────────────────────────────────────────────

describe('GET /reports/summary', () => {
  let token: string;
  let tenantId: number;
  let sessionId: number;
  let deviceId: number;
  let userId: number;

  beforeEach(async () => {
    ({ token, tenantId, sessionId, deviceId, userId } = await setup('business'));
  });

  it('gibt Gesamtsummen + leeres by_day zurück wenn keine Bons vorhanden', async () => {
    const res = await request(app)
      .get(`/reports/summary?from=${TODAY}&to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.from).toBe(TODAY);
    expect(res.body.to).toBe(TODAY);
    expect(res.body.receipt_count).toBe(0);
    expect(res.body.total_gross_cents).toBe(0);
    expect(res.body.by_day).toEqual([]);
  });

  it('aggregiert korrekt über mehrere Tage', async () => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const YESTERDAY = yesterday.toISOString().slice(0, 10);

    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 2500, dateOverride: YESTERDAY });
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 1190, dateOverride: TODAY });

    const res = await request(app)
      .get(`/reports/summary?from=${YESTERDAY}&to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.receipt_count).toBe(2);
    expect(res.body.total_gross_cents).toBe(2500 + 1190);
    expect(res.body.by_day).toHaveLength(2);

    const dayYesterday = res.body.by_day.find((d: any) => d.date === YESTERDAY);
    const dayToday     = res.body.by_day.find((d: any) => d.date === TODAY);
    expect(dayYesterday.total_gross_cents).toBe(2500);
    expect(dayToday.total_gross_cents).toBe(1190);
  });

  it('422 wenn from fehlt', async () => {
    const res = await request(app)
      .get(`/reports/summary?to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
  });

  it('422 wenn from nach to liegt', async () => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const res = await request(app)
      .get(`/reports/summary?from=${TODAY}&to=${yesterday.toISOString().slice(0, 10)}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body.error).toMatch(/from/);
  });

  it('403 wenn Starter-Plan zu weit zurückschaut', async () => {
    const { token: starterToken } = await setup('starter');
    const old = new Date();
    old.setDate(old.getDate() - 60);
    const res = await request(app)
      .get(`/reports/summary?from=${old.toISOString().slice(0, 10)}&to=${TODAY}`)
      .set('Authorization', `Bearer ${starterToken}`);
    expect(res.status).toBe(403);
  });

  it('Tenant-Isolation: Tenant B sieht keine Daten von Tenant A', async () => {
    await insertPaidReceipt(tenantId, sessionId, deviceId, userId, { vat19GrossCents: 9900 });

    const { token: tokenB } = await setup('business');
    const res = await request(app)
      .get(`/reports/summary?from=${TODAY}&to=${TODAY}`)
      .set('Authorization', `Bearer ${tokenB}`);
    expect(res.status).toBe(200);
    expect(res.body.total_gross_cents).toBe(0);
    expect(res.body.receipt_count).toBe(0);
  });
});

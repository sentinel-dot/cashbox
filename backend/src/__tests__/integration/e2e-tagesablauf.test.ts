import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── E2E-Durchstich (TC-E2E, UC-01…UC-09) ────────────────────────────────────
// Ein kompletter Kassentag in einem Test: Session auf → Orders (bar/karte/
// gemischt/split) → Storno → Movements → Close. Prüft die sessionübergreifenden
// Invarianten, die kein Domänen-Test einzeln sieht:
//   REQ-GOBD-002  Bon-Nummern lückenlos 1…N
//   REQ-GOBD-004  Storno nettet (receipts- und payments-Summen der Order == 0)
//   REQ-GOBD-011  expected_cash exakt, Z-Bericht konsistent + persistiert
// Läuft bewusst in EINEM it() — afterEach räumt die Test-DB (setup.ts).

async function setup(conn: any) {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('E2E GmbH', 'Str. 1, Berlin', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@e2e.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok-e2e').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad Theke', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  // Produkte mit gemischten Sätzen und krummen Beträgen (Testdaten-Regel §5)
  const mkProduct = async (name: string, cents: number, vat: '7' | '19') => {
    const [p] = await conn.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
       VALUES (?, ?, ?, ?, ?)`,
      [tenantId, name, cents, vat, vat]
    );
    return p.insertId as number;
  };
  const p19a = await mkProduct('Shisha Premium', 2500, '19');
  const p19b = await mkProduct('Shisha Standard', 1900, '19');
  const p7   = await mkProduct('Tee Minze', 350, '7');

  return { tenantId, userId, deviceId, token, p19a, p19b, p7 };
}

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

async function createOrderWithItems(
  token: string,
  items: Array<{ productId: number; quantity?: number }>
): Promise<{ orderId: number; itemIds: number[]; itemTotals: number[] }> {
  const orderRes = await request(app).post('/orders').set(auth(token)).send({});
  expect(orderRes.status).toBe(201);
  const orderId = orderRes.body.id as number;
  const itemIds: number[] = [];
  const itemTotals: number[] = [];
  for (const item of items) {
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set(auth(token))
      .send({ product_id: item.productId, quantity: item.quantity ?? 1 });
    expect(res.status).toBe(201);
    itemIds.push(res.body.id as number);
    itemTotals.push(res.body.subtotal_cents as number);
  }
  return { orderId, itemIds, itemTotals };
}

describe('E2E: kompletter Kassentag', () => {
  let ctx: Awaited<ReturnType<typeof setup>>;

  beforeEach(async () => { ctx = await setup(db); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('Session → bar/karte/gemischt/split → Storno → Movements → Close: alle Invarianten halten', async () => {
    const { token, tenantId } = ctx;

    // ── UC-01: Schicht öffnen mit 100,00 € Wechselgeld ──
    const openRes = await request(app).post('/sessions/open').set(auth(token))
      .send({ opening_cash_cents: 10000 });
    expect(openRes.status).toBe(201);
    const sessionId = openRes.body.id as number;

    // ── UC-03: Order A — 2×19 %, bar 44,00 € → Bon 1 ──
    const orderA = await createOrderWithItems(token, [
      { productId: ctx.p19a }, { productId: ctx.p19b },
    ]);
    const payA = await request(app).post(`/orders/${orderA.orderId}/pay`).set(auth(token))
      .send({ method: 'cash', amount_cents: 4400 });
    expect(payA.status).toBe(201);
    expect(payA.body.receipt_number).toBe(1);

    // ── UC-04: Order B — 7 % + 19 %, karte 22,50 € → Bon 2 ──
    const orderB = await createOrderWithItems(token, [
      { productId: ctx.p7 }, { productId: ctx.p19b },
    ]);
    const payB = await request(app).post(`/orders/${orderB.orderId}/pay`).set(auth(token))
      .send({ method: 'card', amount_cents: 2250 });
    expect(payB.status).toBe(201);
    expect(payB.body.receipt_number).toBe(2);
    // MwSt getrennt aufgeschlüsselt, Brutto == Netto + Steuer je Satz
    expect(payB.body.vat_7_net_cents + payB.body.vat_7_tax_cents).toBe(350);
    expect(payB.body.vat_19_net_cents + payB.body.vat_19_tax_cents).toBe(1900);

    // ── UC-05: Order C — gemischt 10,00 € bar + 15,00 € karte → Bon 3 ──
    const orderC = await createOrderWithItems(token, [{ productId: ctx.p19a }]);
    const payC = await request(app).post(`/orders/${orderC.orderId}/pay`).set(auth(token))
      .send({ payments: [
        { method: 'cash', amount_cents: 1000 },
        { method: 'card', amount_cents: 1500 },
      ] });
    expect(payC.status).toBe(201);
    expect(payC.body.receipt_number).toBe(3);

    // ── UC-06: Order D — Split in 2 Bons (bar 3,50 € / karte 19,00 €) → Bons 4+5 ──
    const orderD = await createOrderWithItems(token, [
      { productId: ctx.p7 }, { productId: ctx.p19b },
    ]);
    const splitRes = await request(app).post(`/orders/${orderD.orderId}/pay/split`).set(auth(token))
      .send({ splits: [
        { order_item_ids: [orderD.itemIds[0]], payments: [{ method: 'cash', amount_cents: 350 }] },
        { order_item_ids: [orderD.itemIds[1]], payments: [{ method: 'card', amount_cents: 1900 }] },
      ] });
    expect(splitRes.status).toBe(201);
    expect(splitRes.body.receipts.map((r: any) => r.receipt_number)).toEqual([4, 5]);

    // ── UC-07: Storno Bon 1 (Original bleibt, Gegenbuchung → Bon 6) ──
    const cancelRes = await request(app)
      .post(`/receipts/${payA.body.receipt_id}/cancel`).set(auth(token))
      .send({ reason: 'Gast reklamiert — falsche Bestellung' });
    expect(cancelRes.status).toBe(201);

    // ── UC-08: Einlage 5,00 €, Entnahme 20,00 € ──
    const dep = await request(app).post(`/sessions/${sessionId}/movements`).set(auth(token))
      .send({ type: 'deposit', amount_cents: 500, reason: 'Wechselgeld nachgelegt' });
    expect(dep.status).toBe(201);
    const wd = await request(app).post(`/sessions/${sessionId}/movements`).set(auth(token))
      .send({ type: 'withdrawal', amount_cents: 2000, reason: 'Einkauf Kohle' });
    expect(wd.status).toBe(201);

    // ── UC-09: Close blockt solange eine Bestellung offen ist ──
    const orderE = await createOrderWithItems(token, [{ productId: ctx.p7 }]);
    const blockedClose = await request(app).post('/sessions/close').set(auth(token))
      .send({ closing_cash_cents: 0 });
    expect(blockedClose.status).toBe(409);
    expect(blockedClose.body.error).toContain('offene Bestellung');
    const cancelE = await request(app).post(`/orders/${orderE.orderId}/cancel`).set(auth(token))
      .send({ reason: 'Gast gegangen' });
    expect(cancelE.status).toBe(200);

    // ── Kassensturz: expected_cash exakt vorgerechnet ──
    // opening 10000 + bar (4400 + 1000 + 350 − 4400 Storno) + Einlage 500 − Entnahme 2000
    const expectedCash = 10000 + 1350 + 500 - 2000;
    const closeRes = await request(app).post('/sessions/close').set(auth(token))
      .send({ closing_cash_cents: expectedCash });
    expect(closeRes.status).toBe(200);
    expect(closeRes.body.expected_cash_cents).toBe(expectedCash);
    expect(closeRes.body.difference_cents).toBe(0);

    // ── Z-Bericht-Invarianten (REQ-GOBD-011) ──
    // Umsatz: B 2250 + C 2500 + D 2250 = 7000 (A nettet durch Storno auf 0)
    expect(closeRes.body.total_revenue_cents).toBe(7000);
    expect(closeRes.body.total_orders).toBe(4);          // A, B, C, D — Gemischt zählt 1×
    expect(closeRes.body.cancellation_count).toBe(1);
    const paymentsByMethod = Object.fromEntries(
      closeRes.body.payments.map((p: any) => [p.method, p.total_amount_cents])
    );
    expect(paymentsByMethod['cash']).toBe(1350);
    expect(paymentsByMethod['card']).toBe(5650);
    // MwSt: 7 % = 350 (Bon 2) + 350 (Bon 4) = 700; 19 % = 4400+1900+2500+1900−4400 = 6300
    expect(closeRes.body.vat_breakdown).toEqual([
      { vat_rate: '7',  net_plus_vat_cents: 700 },
      { vat_rate: '19', net_plus_vat_cents: 6300 },
    ]);

    // ── Storno nettet vollständig (REQ-GOBD-004) ──
    const [receiptSum] = await db.execute<any[]>(
      `SELECT COALESCE(SUM(total_gross_cents), 0) AS s FROM receipts
       WHERE order_id = ? AND tenant_id = ? AND status = 'active'`,
      [orderA.orderId, tenantId]
    );
    expect(Number(receiptSum[0].s)).toBe(0);
    const [paymentSum] = await db.execute<any[]>(
      `SELECT COALESCE(SUM(p.amount_cents), 0) AS s FROM payments p
       JOIN receipts r ON r.id = p.receipt_id
       WHERE p.order_id = ? AND r.tenant_id = ?`,
      [orderA.orderId, tenantId]
    );
    expect(Number(paymentSum[0].s)).toBe(0);

    // ── Bon-Nummern lückenlos 1…6 (REQ-GOBD-002) ──
    const [numbers] = await db.execute<any[]>(
      `SELECT receipt_number FROM receipts WHERE tenant_id = ? ORDER BY receipt_number ASC`,
      [tenantId]
    );
    expect(numbers.map((r: any) => r.receipt_number)).toEqual([1, 2, 3, 4, 5, 6]);

    // ── Persistierter Z-Bericht == Close-Response (REQ-GOBD-011) ──
    const zRes = await request(app).get(`/sessions/${sessionId}/z-report`).set(auth(token));
    expect(zRes.status).toBe(200);
    expect(zRes.body.id).toBe(closeRes.body.z_report_id);
    expect(zRes.body.report.expected_cash_cents).toBe(expectedCash);
    expect(zRes.body.report.difference_cents).toBe(0);
    expect(zRes.body.report.total_revenue_cents).toBe(7000);
    expect(zRes.body.report.payments).toEqual(closeRes.body.payments);
    expect(zRes.body.report.vat_breakdown).toEqual(closeRes.body.vat_breakdown);
  });

  it('Tenant-Isolation: fremder Tenant sieht Session, Bons und Z-Bericht nicht', async () => {
    const { token } = ctx;
    const openRes = await request(app).post('/sessions/open').set(auth(token))
      .send({ opening_cash_cents: 0 });
    const sessionId = openRes.body.id as number;
    const orderA = await createOrderWithItems(token, [{ productId: ctx.p7 }]);
    const payA = await request(app).post(`/orders/${orderA.orderId}/pay`).set(auth(token))
      .send({ method: 'cash', amount_cents: 350 });
    await request(app).post('/sessions/close').set(auth(token)).send({ closing_cash_cents: 350 });

    // Zweiter Tenant
    const other = await setupOtherTenant();
    expect((await request(app).get(`/sessions/${sessionId}`).set(auth(other))).status).toBe(404);
    expect((await request(app).get(`/sessions/${sessionId}/z-report`).set(auth(other))).status).toBe(404);
    expect((await request(app).get(`/receipts/${payA.body.receipt_id}`).set(auth(other))).status).toBe(404);
  });
});

async function setupOtherTenant(): Promise<string> {
  const [t2] = await db.execute<any>(
    `INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('Fremd', 'X', 'starter', 'active')`
  );
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [t2.insertId]);
  const hash = await bcrypt.hash('pw', 10);
  const [u2] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'F', 'f@f.de', ?, 'owner')`,
    [t2.insertId, hash]
  );
  const tokenHash = crypto.createHash('sha256').update('tok-fremd').digest('hex');
  const [d2] = await db.execute<any>(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad F', ?)`,
    [t2.insertId, tokenHash]
  );
  return jwt.sign(
    { userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
}

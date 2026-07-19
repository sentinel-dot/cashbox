import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Nebenläufigkeits-Tests (TC-C, UC-11) ────────────────────────────────────
// Echte parallele Requests (Promise.all über supertest) gegen die im Audit #2
// eingeführten Locks:
//   REQ-GOBD-002  genau eine Bon-Nummer je Zahlung
//   REQ-GOBD-006  Session-Lock: kein Bon bucht in eine geschlossene Session
//   REQ-GOBD-007  Doppel-Storno unmöglich
// Races sind nichtdeterministisch → Assertions prüfen legale ERGEBNISMENGEN
// (z.B. Status-Multiset {201, 409}), nie Reihenfolgen; jede Race läuft mehrfach.

const RACE_ROUNDS = 5;

async function setup(conn: any) {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Race GmbH', 'Str. 1, Berlin', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@race.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok-race').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  const [p] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha', 2500, '19', '19')`,
    [tenantId]
  );

  return { tenantId, userId, deviceId, token, productId: p.insertId as number };
}

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

async function openSession(token: string): Promise<number> {
  const res = await request(app).post('/sessions/open').set(auth(token)).send({ opening_cash_cents: 0 });
  expect(res.status).toBe(201);
  return res.body.id as number;
}

async function createPaidOrder(token: string, productId: number): Promise<{ orderId: number; receiptId: number }> {
  const orderRes = await request(app).post('/orders').set(auth(token)).send({});
  const orderId = orderRes.body.id as number;
  await request(app).post(`/orders/${orderId}/items`).set(auth(token))
    .send({ product_id: productId, quantity: 1 });
  const payRes = await request(app).post(`/orders/${orderId}/pay`).set(auth(token))
    .send({ method: 'cash', amount_cents: 2500 });
  expect(payRes.status).toBe(201);
  return { orderId, receiptId: payRes.body.receipt_id as number };
}

describe('Nebenläufigkeit: parallele Doppel-Requests', () => {
  let ctx: Awaited<ReturnType<typeof setup>>;

  beforeEach(async () => { ctx = await setup(db); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('Doppel-Pay: genau einer gewinnt, genau 1 Bon + 1 Nummer', async () => {
    const { token, tenantId, productId } = ctx;
    await openSession(token);

    for (let round = 0; round < RACE_ROUNDS; round++) {
      const orderRes = await request(app).post('/orders').set(auth(token)).send({});
      const orderId = orderRes.body.id as number;
      await request(app).post(`/orders/${orderId}/items`).set(auth(token))
        .send({ product_id: productId, quantity: 1 });

      const [a, b] = await Promise.all([
        request(app).post(`/orders/${orderId}/pay`).set(auth(token)).send({ method: 'cash', amount_cents: 2500 }),
        request(app).post(`/orders/${orderId}/pay`).set(auth(token)).send({ method: 'card', amount_cents: 2500 }),
      ]);
      expect([a.status, b.status].sort()).toEqual([201, 409]);

      // Genau 1 aktiver Bon und genau 1 payments-Zeile für diese Order
      const [receipts] = await db.execute<any[]>(
        `SELECT COUNT(*) AS cnt FROM receipts WHERE order_id = ? AND tenant_id = ? AND status = 'active'`,
        [orderId, tenantId]
      );
      expect(Number(receipts[0].cnt)).toBe(1);
      const [payments] = await db.execute<any[]>(
        `SELECT COUNT(*) AS cnt FROM payments WHERE order_id = ?`,
        [orderId]
      );
      expect(Number(payments[0].cnt)).toBe(1);
    }

    // Bon-Nummern trotz Races lückenlos: RACE_ROUNDS Bons → 1…RACE_ROUNDS
    const [seq] = await db.execute<any[]>(
      `SELECT last_number FROM receipt_sequences WHERE tenant_id = ?`, [ctx.tenantId]
    );
    expect(Number(seq[0].last_number)).toBe(RACE_ROUNDS);
  });

  it('Doppel-Storno: genau eine Gegenbuchung, payments netten exakt einmal', async () => {
    const { token, tenantId, productId } = ctx;
    await openSession(token);

    for (let round = 0; round < RACE_ROUNDS; round++) {
      const { orderId, receiptId } = await createPaidOrder(token, productId);

      const [a, b] = await Promise.all([
        request(app).post(`/receipts/${receiptId}/cancel`).set(auth(token)).send({ reason: 'Race A' }),
        request(app).post(`/receipts/${receiptId}/cancel`).set(auth(token)).send({ reason: 'Race B' }),
      ]);
      expect([a.status, b.status].sort()).toEqual([201, 409]);

      // Genau 1 cancellations-Zeile (UNIQUE-Backstop V008 + FOR-UPDATE-Check)
      const [cancels] = await db.execute<any[]>(
        `SELECT COUNT(*) AS cnt FROM cancellations WHERE original_receipt_id = ?`,
        [receiptId]
      );
      expect(Number(cancels[0].cnt)).toBe(1);

      // Nicht doppelt negiert: Summe aller payments der Order == 0
      const [sum] = await db.execute<any[]>(
        `SELECT COALESCE(SUM(p.amount_cents), 0) AS s FROM payments p
         JOIN receipts r ON r.id = p.receipt_id
         WHERE p.order_id = ? AND r.tenant_id = ?`,
        [orderId, tenantId]
      );
      expect(Number(sum[0].s)).toBe(0);
    }
  });

  it('Pay vs. Close: niemals ein Bon, der im Z-Bericht fehlt', async () => {
    const { token, tenantId, productId } = ctx;

    for (let round = 0; round < RACE_ROUNDS; round++) {
      const sessionId = await openSession(token);
      const orderRes = await request(app).post('/orders').set(auth(token)).send({});
      const orderId = orderRes.body.id as number;
      await request(app).post(`/orders/${orderId}/items`).set(auth(token))
        .send({ product_id: productId, quantity: 1 });

      const [payRes, closeRes] = await Promise.all([
        request(app).post(`/orders/${orderId}/pay`).set(auth(token)).send({ method: 'cash', amount_cents: 2500 }),
        request(app).post('/sessions/close').set(auth(token)).send({ closing_cash_cents: 0 }),
      ]);

      // Legale Ausgänge (die Order ist bis zum Pay 'open' und blockiert close):
      //   pay 201 ∧ close 409 (offene Bestellung ODER Race verloren)
      //   pay 409 (Session geschlossen) ∧ close 200  — close kann nur gewinnen,
      //     wenn payOrder die Order schon auf paid hatte? Nein: dann wäre close
      //     nicht an der offenen Order gescheitert. Deshalb gilt:
      //   close 200 ⇒ pay hat vorher committet ∧ Bon ist im Z-Bericht
      const outcome = [payRes.status, closeRes.status];
      expect([
        JSON.stringify([201, 200]),
        JSON.stringify([201, 409]),
        JSON.stringify([409, 200]),
      ]).toContain(JSON.stringify(outcome));

      // Verbotener Zustand: aktiver Bon existiert, Session ist zu, Bon fehlt im Z-Bericht
      const [receiptRows] = await db.execute<any[]>(
        `SELECT id, session_id FROM receipts WHERE order_id = ? AND tenant_id = ? AND status = 'active'`,
        [orderId, tenantId]
      );
      if (receiptRows.length > 0) {
        const [sessionRows] = await db.execute<any[]>(
          `SELECT status FROM cash_register_sessions WHERE id = ?`,
          [receiptRows[0].session_id]
        );
        if (sessionRows[0].status === 'closed') {
          // Bon in geschlossener Session → er MUSS im persistierten Z-Bericht stecken
          const [zRows] = await db.execute<any[]>(
            `SELECT report_json FROM z_reports WHERE session_id = ? AND tenant_id = ?`,
            [receiptRows[0].session_id, tenantId]
          );
          expect(zRows.length).toBe(1);
          const report = typeof zRows[0].report_json === 'string'
            ? JSON.parse(zRows[0].report_json) : zRows[0].report_json;
          expect(report.total_revenue_cents).toBe(2500);
        }
      }

      // Aufräumen für die nächste Runde: Session ggf. noch offen → Order abschließen + schließen
      if (closeRes.status !== 200) {
        if (payRes.status !== 201) {
          await request(app).post(`/orders/${orderId}/cancel`).set(auth(token)).send({ reason: 'Race-Cleanup' });
        }
        const finalClose = await request(app).post('/sessions/close').set(auth(token)).send({ closing_cash_cents: 0 });
        expect(finalClose.status).toBe(200);
      }
    }
  });

  it('Doppel-Close: genau ein Z-Bericht', async () => {
    const { token, tenantId } = ctx;

    for (let round = 0; round < RACE_ROUNDS; round++) {
      const sessionId = await openSession(token);
      const [a, b] = await Promise.all([
        request(app).post('/sessions/close').set(auth(token)).send({ closing_cash_cents: 0 }),
        request(app).post('/sessions/close').set(auth(token)).send({ closing_cash_cents: 0 }),
      ]);
      // Verlierer: 404 (Session nicht mehr offen) oder 409 (Guard im UPDATE)
      const statuses = [a.status, b.status].sort();
      expect(statuses[0]).toBe(200);
      expect([404, 409]).toContain(statuses[1]);

      const [zRows] = await db.execute<any[]>(
        `SELECT COUNT(*) AS cnt FROM z_reports WHERE session_id = ? AND tenant_id = ?`,
        [sessionId, tenantId]
      );
      expect(Number(zRows[0].cnt)).toBe(1);
    }
  });

  it('Doppel-Open: genau eine offene Session pro Gerät', async () => {
    const { token, tenantId } = ctx;

    const [a, b] = await Promise.all([
      request(app).post('/sessions/open').set(auth(token)).send({ opening_cash_cents: 1000 }),
      request(app).post('/sessions/open').set(auth(token)).send({ opening_cash_cents: 2000 }),
    ]);
    expect([a.status, b.status].sort()).toEqual([201, 409]);

    const [open] = await db.execute<any[]>(
      `SELECT COUNT(*) AS cnt FROM cash_register_sessions WHERE tenant_id = ? AND status = 'open'`,
      [tenantId]
    );
    expect(Number(open[0].cnt)).toBe(1);
  });
});

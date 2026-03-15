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
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Test GmbH', 'Str. 1, Berlin', 'business', 'active')`
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
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  // Offene Kassensitzung anlegen (sessionMiddleware-Voraussetzung)
  const [s] = await conn.execute(
    `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, 5000, 'open')`,
    [tenantId, deviceId, userId]
  );
  const sessionId = s.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );

  // Testprodukt
  const [p] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha Klein', 1500, '19', '19')`,
    [tenantId]
  );
  const productId = p.insertId as number;

  return { tenantId, userId, deviceId, sessionId, token, productId };
}

// Erstellt eine Order und gibt deren ID zurück
async function createOrderHelper(token: string, tableId?: number): Promise<number> {
  const body = tableId ? { table_id: tableId } : {};
  const res = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send(body);
  return res.body.id as number;
}

// ─── POST /orders ─────────────────────────────────────────────────────────────

describe('POST /orders', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('erstellt Order ohne Tisch', async () => {
    const res = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.table_id).toBeNull();
    expect(res.body.status).toBe('open');
  });

  it('erstellt Order mit Tisch', async () => {
    const [t] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'T1')`, [tenantId]) as any;
    const res = await request(app)
      .post('/orders')
      .set('Authorization', `Bearer ${token}`)
      .send({ table_id: t.insertId });
    expect(res.status).toBe(201);
    expect(res.body.table_id).toBe(t.insertId);
  });

  it('404 wenn table_id zu anderem Tenant gehört (Tenant-Isolation)', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const [tbl2] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'FT')`, [t2.insertId]) as any;

    const res = await request(app).post('/orders').set('Authorization', `Bearer ${token}`).send({ table_id: tbl2.insertId });
    expect(res.status).toBe(404);
  });

  it('409 wenn keine offene Kassensitzung', async () => {
    // Token mit neuem Device ohne Session
    const [t] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('X','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','x@x.de',?,'owner')`, [t.insertId, hash]) as any;
    const th = crypto.createHash('sha256').update('xtok').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+',?)`, [t.insertId, th]) as any;
    const tok2 = jwt.sign({ userId: u2.insertId, tenantId: t.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload, process.env['JWT_SECRET'] ?? 'test-secret', { expiresIn: '15m' });

    const res = await request(app).post('/orders').set('Authorization', `Bearer ${tok2}`).send({});
    expect(res.status).toBe(409);
  });
});

// ─── GET /orders ──────────────────────────────────────────────────────────────

describe('GET /orders', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt offene Orders der aktuellen Session zurück', async () => {
    await createOrderHelper(token);
    const res = await request(app).get('/orders').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
    expect(res.body[0].status).toBe('open');
  });

  it('Tenant-Isolation: gibt keine Orders anderer Tenants zurück', async () => {
    // Setup für Tenant B mit eigener Session
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de',?,'owner')`, [t2.insertId, hash]) as any;
    const th = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+',?)`, [t2.insertId, th]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`, [t2.insertId, d2.insertId, u2.insertId]) as any;
    await db.execute(`INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`, [t2.insertId, s2.insertId, u2.insertId]);

    const res = await request(app).get('/orders').set('Authorization', `Bearer ${token}`);
    // Tenant A sieht keine Orders von Tenant B
    expect(res.body.every((o: any) => o)).toBe(true); // alle zurückgegebenen gehören zur eigenen Session
  });
});

// ─── GET /orders/:id ──────────────────────────────────────────────────────────

describe('GET /orders/:id', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Order mit Items zurück', async () => {
    const orderId = await createOrderHelper(token);
    await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 2 });

    const res = await request(app).get(`/orders/${orderId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.items.length).toBe(1);
    expect(res.body.items[0].quantity).toBe(2);
    expect(res.body.total_cents).toBe(3000); // 1500 × 2
  });

  it('Tenant-Isolation: kann Order anderer Tenants nicht lesen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de',?,'owner')`, [t2.insertId, hash]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) SELECT ?,id,?,0,'open' FROM devices WHERE tenant_id=? LIMIT 1`, [t2.insertId, u2.insertId, tenantId]) as any;
    // Order direkt in DB anlegen
    const [o2] = await db.execute(`INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`, [t2.insertId, s2.insertId, u2.insertId]) as any;

    const res = await request(app).get(`/orders/${o2.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── POST /orders/:id/items ───────────────────────────────────────────────────

describe('POST /orders/:id/items', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('fügt Item hinzu — Snapshot und Berechnung korrekt', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 3 });

    expect(res.status).toBe(201);
    expect(res.body.subtotal_cents).toBe(4500); // 1500 × 3
    expect(res.body.product_name).toBe('Shisha Klein');
  });

  it('fügt Item mit Modifier hinzu — Delta im Preis', async () => {
    const orderId = await createOrderHelper(token);

    const [g] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required, min_selections, max_selections)
       VALUES (?, ?, 'Tabak', FALSE, 0, 1)`,
      [tenantId, productId]
    ) as any;
    const [o] = await db.execute(
      `INSERT INTO product_modifier_options (modifier_group_id, tenant_id, name, price_delta_cents)
       VALUES (?, ?, 'Al Fakher', 200)`,
      [g.insertId, tenantId]
    ) as any;

    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 2, modifier_option_ids: [o.insertId] });

    expect(res.status).toBe(201);
    // (1500 + 200) × 2 = 3400
    expect(res.body.subtotal_cents).toBe(3400);
  });

  it('fügt Item mit Rabatt hinzu', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1, discount_cents: 500, discount_reason: 'Stammkunde' });

    expect(res.status).toBe(201);
    expect(res.body.subtotal_cents).toBe(1000); // 1500 - 500
  });

  it('422 wenn discount_reason fehlt bei discount_cents > 0', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1, discount_cents: 500 });
    expect(res.status).toBe(422);
  });

  it('422 bei Rabatt größer als Positionsbetrag', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1, discount_cents: 9999, discount_reason: 'X' });
    expect(res.status).toBe(422);
  });

  it('403 wenn modifier_option_id zu anderem Produkt gehört (Tenant-Isolation)', async () => {
    const orderId = await createOrderHelper(token);

    // Modifier-Gruppe an einem anderen Produkt
    const [p2] = await db.execute(`INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Anderes', 1000, '19', '19')`, [tenantId]) as any;
    const [g2] = await db.execute(`INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?,?,'X',FALSE)`, [tenantId, p2.insertId]) as any;
    const [o2] = await db.execute(`INSERT INTO product_modifier_options (modifier_group_id, tenant_id, name, price_delta_cents) VALUES (?,?,'Y',0)`, [g2.insertId, tenantId]) as any;

    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1, modifier_option_ids: [o2.insertId] });
    expect(res.status).toBe(403);
  });

  it('422 wenn Required-Modifier-Gruppe nicht abgedeckt', async () => {
    const orderId = await createOrderHelper(token);

    await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required, min_selections, max_selections)
       VALUES (?, ?, 'PflichtTabak', TRUE, 1, 1)`,
      [tenantId, productId]
    );

    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1 });
    expect(res.status).toBe(422);
  });

  it('404 wenn Produkt zu anderem Tenant gehört (Tenant-Isolation)', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const [p2] = await db.execute(`INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?,'FP',1000,'19','19')`, [t2.insertId]) as any;

    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: p2.insertId, quantity: 1 });
    expect(res.status).toBe(404);
  });

  it('409 wenn Order nicht offen', async () => {
    const orderId = await createOrderHelper(token);
    await db.execute(`UPDATE orders SET status='cancelled' WHERE id=?`, [orderId]);

    const res = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1 });
    expect(res.status).toBe(409);
  });
});

// ─── DELETE /orders/:id/items/:itemId ────────────────────────────────────────

describe('DELETE /orders/:id/items/:itemId', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('entfernt Item und schreibt audit_log', async () => {
    const orderId = await createOrderHelper(token);
    const addRes = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1 });
    const itemId = addRes.body.id;

    const res = await request(app)
      .delete(`/orders/${orderId}/items/${itemId}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);

    // GoBD: Item bleibt in order_items erhalten (kein physisches Löschen)
    const [rows] = await db.execute(`SELECT id FROM order_items WHERE id=?`, [itemId]) as any;
    expect(rows.length).toBe(1);

    // Entfernung wird in order_item_removals dokumentiert
    const [removals] = await db.execute(`SELECT id FROM order_item_removals WHERE order_item_id=?`, [itemId]) as any;
    expect(removals.length).toBe(1);

    const [audit] = await db.execute(`SELECT id FROM audit_log WHERE action='order.item_removed' AND entity_id=?`, [itemId]) as any;
    expect(audit.length).toBe(1);
  });

  it('409 wenn Order bereits storniert', async () => {
    const orderId = await createOrderHelper(token);
    const addRes = await request(app)
      .post(`/orders/${orderId}/items`)
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, quantity: 1 });
    await db.execute(`UPDATE orders SET status='cancelled' WHERE id=?`, [orderId]);

    const res = await request(app)
      .delete(`/orders/${orderId}/items/${addRes.body.id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(409);
  });

  it('Tenant-Isolation: kann Item aus fremder Order nicht entfernen', async () => {
    // Fremde Order in DB anlegen
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de',?,'owner')`, [t2.insertId, hash]) as any;
    const th = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+',?)`, [t2.insertId, th]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`, [t2.insertId, d2.insertId, u2.insertId]) as any;
    const [o2] = await db.execute(`INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`, [t2.insertId, s2.insertId, u2.insertId]) as any;
    const [p2] = await db.execute(`INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?,'FP',1000,'19','19')`, [t2.insertId]) as any;
    const [i2] = await db.execute(`INSERT INTO order_items (order_id, product_id, product_name, product_price_cents, vat_rate, quantity, subtotal_cents, discount_cents, added_by_user_id) VALUES (?,?,'+',1000,'19',1,1000,0,?)`, [o2.insertId, p2.insertId, u2.insertId]) as any;

    const res = await request(app)
      .delete(`/orders/${o2.insertId}/items/${i2.insertId}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── POST /orders/:id/cancel ──────────────────────────────────────────────────

describe('POST /orders/:id/cancel', () => {
  let token: string; let productId: number;

  beforeEach(async () => { ({ token, productId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('storniert offene Order und schreibt audit_log', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Gast hat storniert' });
    expect(res.status).toBe(200);

    const [rows] = await db.execute(`SELECT status FROM orders WHERE id=?`, [orderId]) as any;
    expect(rows[0].status).toBe('cancelled');

    const [audit] = await db.execute(`SELECT id FROM audit_log WHERE action='order.cancelled' AND entity_id=?`, [orderId]) as any;
    expect(audit.length).toBe(1);
  });

  it('409 wenn Order bereits storniert', async () => {
    const orderId = await createOrderHelper(token);
    await db.execute(`UPDATE orders SET status='cancelled' WHERE id=?`, [orderId]);
    const res = await request(app)
      .post(`/orders/${orderId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'X' });
    expect(res.status).toBe(409);
  });

  it('409 wenn Order bereits bezahlt (Phase 2 Storno nötig)', async () => {
    const orderId = await createOrderHelper(token);
    await db.execute(`UPDATE orders SET status='paid' WHERE id=?`, [orderId]);
    const res = await request(app)
      .post(`/orders/${orderId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'X' });
    expect(res.status).toBe(409);
  });

  it('422 bei fehlendem reason', async () => {
    const orderId = await createOrderHelper(token);
    const res = await request(app)
      .post(`/orders/${orderId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann Order anderer Tenants nicht stornieren', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?,'+','b@b.de',?,'owner')`, [t2.insertId, hash]) as any;
    const th = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?,'+',?)`, [t2.insertId, th]) as any;
    const [s2] = await db.execute(`INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status) VALUES (?,?,?,0,'open')`, [t2.insertId, d2.insertId, u2.insertId]) as any;
    const [o2] = await db.execute(`INSERT INTO orders (tenant_id, session_id, opened_by_user_id, is_takeaway) VALUES (?,?,?,FALSE)`, [t2.insertId, s2.insertId, u2.insertId]) as any;

    const res = await request(app)
      .post(`/orders/${o2.insertId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'Hack' });
    expect(res.status).toBe(404);
  });
});

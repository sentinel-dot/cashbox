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
     VALUES ('ModTest GmbH', 'Str. 1, Berlin', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'mod@t.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const tokenHash = crypto.createHash('sha256').update('tok2').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const token = jwt.sign(
    { userId: u.insertId, tenantId, deviceId: d.insertId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  const [p] = await conn.execute(
    `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
     VALUES (?, 'Shisha', 2500, '19', '19')`,
    [tenantId]
  );
  return { tenantId, token, productId: p.insertId as number };
}

// ─── POST /modifier-groups ────────────────────────────────────────────────────

describe('POST /modifier-groups', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('legt Gruppe mit product_id an', async () => {
    const res = await request(app)
      .post('/modifier-groups')
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, name: 'Tabaksorte', is_required: true, min_selections: 1, max_selections: 1 });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.is_required).toBe(true);
  });

  it('422 wenn beide product_id und category_id angegeben', async () => {
    const [c] = await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'Kat')`, [tenantId]) as any;
    const res = await request(app)
      .post('/modifier-groups')
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: productId, category_id: c.insertId, name: 'X', is_required: false, min_selections: 0 });
    expect(res.status).toBe(422);
  });

  it('422 wenn weder product_id noch category_id angegeben', async () => {
    const res = await request(app)
      .post('/modifier-groups')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', is_required: false, min_selections: 0 });
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: product_id muss zum Tenant gehören', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [p2] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Fremd', 1000, '19', '19')`,
      [t2.insertId]
    ) as any;
    const res = await request(app)
      .post('/modifier-groups')
      .set('Authorization', `Bearer ${token}`)
      .send({ product_id: p2.insertId, name: 'X', is_required: false, min_selections: 0 });
    expect(res.status).toBe(404);
  });
});

// ─── DELETE /modifier-groups/:id ─────────────────────────────────────────────

describe('DELETE /modifier-groups/:id', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => { ({ token, tenantId, productId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('deaktiviert Gruppe und alle Optionen', async () => {
    const [g] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?, ?, 'Extras', FALSE)`,
      [tenantId, productId]
    ) as any;
    const [o] = await db.execute(
      `INSERT INTO product_modifier_options (modifier_group_id, tenant_id, name, price_delta_cents) VALUES (?, ?, 'Eis', 0)`,
      [g.insertId, tenantId]
    ) as any;

    const res = await request(app).delete(`/modifier-groups/${g.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);

    // Option auch deaktiviert
    const [optRow] = await db.execute('SELECT is_active FROM product_modifier_options WHERE id = ?', [o.insertId]) as any;
    expect(optRow[0].is_active).toBe(0);
  });

  it('Tenant-Isolation: kann Gruppe anderer Tenants nicht löschen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [p2] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Fremd', 1000, '19', '19')`,
      [t2.insertId]
    ) as any;
    const [g2] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?, ?, 'Fremd', FALSE)`,
      [t2.insertId, p2.insertId]
    ) as any;
    const res = await request(app).delete(`/modifier-groups/${g2.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── POST /modifier-groups/:id/options ───────────────────────────────────────

describe('POST /modifier-groups/:id/options', () => {
  let token: string; let tenantId: number; let groupId: number;

  beforeEach(async () => {
    const data = await setup(db);
    token = data.token; tenantId = data.tenantId;
    const [g] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?, ?, 'Tabak', TRUE)`,
      [tenantId, data.productId]
    ) as any;
    groupId = g.insertId;
  });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('legt Option an', async () => {
    const res = await request(app)
      .post(`/modifier-groups/${groupId}/options`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Al Fakher Mint', price_delta_cents: 0 });
    expect(res.status).toBe(201);
    expect(res.body.price_delta_cents).toBe(0);
  });

  it('legt Option mit Aufpreis an', async () => {
    const res = await request(app)
      .post(`/modifier-groups/${groupId}/options`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Premium XY', price_delta_cents: 300 });
    expect(res.status).toBe(201);
    expect(res.body.price_delta_cents).toBe(300);
  });

  it('422 bei negativem price_delta_cents', async () => {
    const res = await request(app)
      .post(`/modifier-groups/${groupId}/options`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Rabatt', price_delta_cents: -100 });
    expect(res.status).toBe(422);
  });

  it('422 bei float price_delta_cents', async () => {
    const res = await request(app)
      .post(`/modifier-groups/${groupId}/options`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', price_delta_cents: 1.5 });
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann keine Option in fremde Gruppe schreiben', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [p2] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Fremd', 1000, '19', '19')`,
      [t2.insertId]
    ) as any;
    const [g2] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?, ?, 'FG', FALSE)`,
      [t2.insertId, p2.insertId]
    ) as any;
    const res = await request(app)
      .post(`/modifier-groups/${g2.insertId}/options`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Hack', price_delta_cents: 0 });
    expect(res.status).toBe(404);
  });
});

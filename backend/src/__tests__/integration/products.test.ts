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

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}

// ─── Kategorien ───────────────────────────────────────────────────────────────

describe('GET /products/categories', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt aktive Kategorien zurück', async () => {
    await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'Shisha')`, [tenantId]);
    const res = await request(app).get('/products/categories').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.some((c: any) => c.name === 'Shisha')).toBe(true);
  });

  it('Tenant-Isolation: zeigt keine Kategorien anderer Tenants', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'FremdKat')`, [t2.insertId]);

    const res = await request(app).get('/products/categories').set('Authorization', `Bearer ${token}`);
    expect(res.body.every((c: any) => c.name !== 'FremdKat')).toBe(true);
  });
});

describe('POST /products/categories', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('legt neue Kategorie an', async () => {
    const res = await request(app)
      .post('/products/categories')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Getränke', color: '#FF0000', sort_order: 1 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.name).toBe('Getränke');
  });

  it('422 bei fehlendem name', async () => {
    const res = await request(app).post('/products/categories').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(422);
  });

  it('422 bei ungültigem Hex-Code', async () => {
    const res = await request(app)
      .post('/products/categories')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', color: 'rot' });
    expect(res.status).toBe(422);
  });
});

describe('DELETE /products/categories/:id', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('löscht leere Kategorie', async () => {
    const [c] = await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'Leer')`, [tenantId]) as any;
    const res = await request(app).delete(`/products/categories/${c.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });

  it('409 wenn noch aktive Produkte in Kategorie', async () => {
    const [c] = await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'Voll')`, [tenantId]) as any;
    await db.execute(
      `INSERT INTO products (tenant_id, category_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
       VALUES (?, ?, 'Produkt', 1000, '19', '19')`,
      [tenantId, c.insertId]
    );
    const res = await request(app).delete(`/products/categories/${c.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(409);
  });

  it('Tenant-Isolation: kann Kategorie anderer Tenants nicht löschen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [c2] = await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'FremdKat')`, [t2.insertId]) as any;

    const res = await request(app).delete(`/products/categories/${c2.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── Produkte ─────────────────────────────────────────────────────────────────

describe('POST /products', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('legt Produkt an und schreibt product_price_history', async () => {
    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Shisha Klein', price_cents: 1500, vat_rate_inhouse: '19' });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.price_cents).toBe(1500);

    // product_price_history-Eintrag vorhanden
    const [hist] = await db.execute(
      'SELECT * FROM product_price_history WHERE product_id = ?',
      [res.body.id]
    ) as any;
    expect(hist.length).toBe(1);
    expect(hist[0].price_cents).toBe(1500);
  });

  it('422 bei fehlendem price_cents', async () => {
    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', vat_rate_inhouse: '19' });
    expect(res.status).toBe(422);
  });

  it('422 bei ungültiger vat_rate', async () => {
    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', price_cents: 1000, vat_rate_inhouse: '13' });
    expect(res.status).toBe(422);
  });

  it('422 bei float price_cents', async () => {
    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', price_cents: 9.99, vat_rate_inhouse: '19' });
    expect(res.status).toBe(422);
  });

  it('404 wenn category_id zu anderem Tenant gehört (Tenant-Isolation)', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [c2] = await db.execute(`INSERT INTO product_categories (tenant_id, name) VALUES (?, 'FremdKat')`, [t2.insertId]) as any;

    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', price_cents: 1000, vat_rate_inhouse: '19', category_id: c2.insertId });
    expect(res.status).toBe(404);
  });
});

describe('PATCH /products/:id', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));
    const [p] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
       VALUES (?, 'Shisha', 2000, '19', '19')`,
      [tenantId]
    ) as any;
    productId = p.insertId;
  });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('aktualisiert name', async () => {
    const res = await request(app)
      .patch(`/products/${productId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Shisha Groß' });
    expect(res.status).toBe(200);
  });

  it('400 wenn price_cents im Body', async () => {
    const res = await request(app)
      .patch(`/products/${productId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ price_cents: 9999 });
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('hint');
  });

  it('400 wenn vat_rate_inhouse im Body', async () => {
    const res = await request(app)
      .patch(`/products/${productId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ vat_rate_inhouse: '7' });
    expect(res.status).toBe(400);
  });

  it('Tenant-Isolation: kann Produkt anderer Tenants nicht ändern', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [p2] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Fremdes Produkt', 1000, '19', '19')`,
      [t2.insertId]
    ) as any;
    const res = await request(app)
      .patch(`/products/${p2.insertId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Gehackt' });
    expect(res.status).toBe(404);
  });
});

describe('GET /products (nested response)', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt Produkte mit Modifier-Gruppen nested zurück', async () => {
    const [p] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway) VALUES (?, 'Shisha', 2500, '19', '19')`,
      [tenantId]
    ) as any;
    const [g] = await db.execute(
      `INSERT INTO product_modifier_groups (tenant_id, product_id, name, is_required) VALUES (?, ?, 'Tabak', TRUE)`,
      [tenantId, p.insertId]
    ) as any;
    await db.execute(
      `INSERT INTO product_modifier_options (modifier_group_id, tenant_id, name, price_delta_cents) VALUES (?, ?, 'Minze', 0)`,
      [g.insertId, tenantId]
    );

    const res = await request(app).get('/products').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const product = res.body.find((p: any) => p.name === 'Shisha');
    expect(product).toBeDefined();
    expect(product.modifier_groups.length).toBe(1);
    expect(product.modifier_groups[0].options.length).toBe(1);
  });
});

// ─── POST /products/:id/price ─────────────────────────────────────────────────

describe('POST /products/:id/price', () => {
  let token: string; let tenantId: number; let productId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));
    const [p] = await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
       VALUES (?, 'Shisha', 2000, '19', '19')`,
      [tenantId]
    ) as any;
    productId = p.insertId;
  });
  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  // a) neuer Eintrag in product_price_history
  it('a) schreibt neuen Eintrag in product_price_history', async () => {
    const res = await request(app)
      .post(`/products/${productId}/price`)
      .set('Authorization', `Bearer ${token}`)
      .send({ price_cents: 2500 });

    expect(res.status).toBe(201);
    expect(res.body.price_cents).toBe(2500);

    const [rows] = await db.execute<any[]>(
      `SELECT price_cents FROM product_price_history WHERE product_id = ? AND tenant_id = ?`,
      [productId, tenantId]
    );
    const prices = rows.map(r => r.price_cents);
    expect(prices).toContain(2500);
  });

  // b) products.price_cents bleibt UNVERÄNDERT (GoBD: immutable)
  it('b) ändert products.price_cents nicht (GoBD: immutable)', async () => {
    await request(app)
      .post(`/products/${productId}/price`)
      .set('Authorization', `Bearer ${token}`)
      .send({ price_cents: 3000 });

    const [rows] = await db.execute<any[]>(
      `SELECT price_cents FROM products WHERE id = ? AND tenant_id = ?`,
      [productId, tenantId]
    );
    expect(rows[0].price_cents).toBe(2000); // Original-Preis unverändert
  });

  // c) PATCH mit price_cents wird abgewiesen (guard in Route)
  it('c) PATCH /products/:id mit price_cents → 400 mit hint', async () => {
    const res = await request(app)
      .patch(`/products/${productId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ price_cents: 9999 });

    expect(res.status).toBe(400);
    expect(res.body.hint).toContain('/products/:id/price');
  });

  it('Validierungsfehler: fehlendes price_cents → 422', async () => {
    const res = await request(app)
      .post(`/products/${productId}/price`)
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann Preis fremder Produkte nicht ändern', async () => {
    const { token: tokenB } = await setup(db);
    const res = await request(app)
      .post(`/products/${productId}/price`)
      .set('Authorization', `Bearer ${tokenB}`)
      .send({ price_cents: 9999 });
    expect(res.status).toBe(404);
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app)
      .post(`/products/${productId}/price`)
      .send({ price_cents: 2500 });
    expect(res.status).toBe(401);
  });
});

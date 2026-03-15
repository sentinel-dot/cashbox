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

// ─── Zonen ───────────────────────────────────────────────────────────────────

describe('GET /tables/zones', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Zonen des Tenants zurück', async () => {
    await db.execute(`INSERT INTO zones (tenant_id, name, sort_order) VALUES (?, 'Terrasse', 1)`, [tenantId]);
    const res = await request(app).get('/tables/zones').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.some((z: any) => z.name === 'Terrasse')).toBe(true);
  });

  it('Tenant-Isolation: zeigt keine Zonen anderer Tenants', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'FremdZone')`, [t2.insertId]);

    const res = await request(app).get('/tables/zones').set('Authorization', `Bearer ${token}`);
    expect(res.body.every((z: any) => z.name !== 'FremdZone')).toBe(true);
  });
});

describe('POST /tables/zones', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('legt neue Zone an', async () => {
    const res = await request(app)
      .post('/tables/zones')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Innen', sort_order: 0 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.name).toBe('Innen');
  });

  it('422 bei fehlendem name', async () => {
    const res = await request(app).post('/tables/zones').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(422);
  });
});

describe('PATCH /tables/zones/:id', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('aktualisiert Zone', async () => {
    const [z] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'Alt')`, [tenantId]) as any;
    const res = await request(app)
      .patch(`/tables/zones/${z.insertId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Neu' });
    expect(res.status).toBe(200);
  });

  it('Tenant-Isolation: kann Zone anderer Tenants nicht ändern', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [z2] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'FremdZone')`, [t2.insertId]) as any;

    const res = await request(app)
      .patch(`/tables/zones/${z2.insertId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Gehackt' });
    expect(res.status).toBe(404);
  });

  it('422 bei leerem Body', async () => {
    const [z] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'X')`, [tenantId]) as any;
    const res = await request(app)
      .patch(`/tables/zones/${z.insertId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });
});

// ─── Tische ──────────────────────────────────────────────────────────────────

describe('GET /tables', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt aktive Tische mit Zone zurück', async () => {
    const [z] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'Außen')`, [tenantId]) as any;
    await db.execute(`INSERT INTO tables (tenant_id, zone_id, name) VALUES (?, ?, 'Tisch 1')`, [tenantId, z.insertId]);

    const res = await request(app).get('/tables').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const tisch = res.body.find((t: any) => t.name === 'Tisch 1');
    expect(tisch).toBeDefined();
    expect(tisch.zone.name).toBe('Außen');
    expect(tisch.open_orders_count).toBe(0);
  });

  it('gibt Tisch ohne Zone zurück (null)', async () => {
    await db.execute(`INSERT INTO tables (tenant_id, zone_id, name) VALUES (?, NULL, 'Theke')`, [tenantId]);
    const res = await request(app).get('/tables').set('Authorization', `Bearer ${token}`);
    const theke = res.body.find((t: any) => t.name === 'Theke');
    expect(theke.zone).toBeNull();
  });

  it('Tenant-Isolation: zeigt keine Tische anderer Tenants', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'FremdTisch')`, [t2.insertId]);

    const res = await request(app).get('/tables').set('Authorization', `Bearer ${token}`);
    expect(res.body.every((t: any) => t.name !== 'FremdTisch')).toBe(true);
  });
});

describe('POST /tables', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('legt Tisch ohne Zone an', async () => {
    const res = await request(app)
      .post('/tables')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Tisch 5' });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.zone_id).toBeNull();
  });

  it('legt Tisch mit Zone an', async () => {
    const [z] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'Garten')`, [tenantId]) as any;
    const res = await request(app)
      .post('/tables')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'G1', zone_id: z.insertId });
    expect(res.status).toBe(201);
    expect(res.body.zone_id).toBe(z.insertId);
  });

  it('404 wenn zone_id zu anderem Tenant gehört (Tenant-Isolation)', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [z2] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'FremdZone')`, [t2.insertId]) as any;

    const res = await request(app)
      .post('/tables')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', zone_id: z2.insertId });
    expect(res.status).toBe(404);
  });

  it('422 bei fehlendem name', async () => {
    const res = await request(app).post('/tables').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(422);
  });
});

describe('PATCH /tables/:id', () => {
  let token: string; let tenantId: number; let tableId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));
    const [t] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'Alt')`, [tenantId]) as any;
    tableId = t.insertId;
  });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('aktualisiert Tischname', async () => {
    const res = await request(app)
      .patch(`/tables/${tableId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Neu' });
    expect(res.status).toBe(200);
  });

  it('setzt Zone auf null', async () => {
    const [z] = await db.execute(`INSERT INTO zones (tenant_id, name) VALUES (?, 'Z')`, [tenantId]) as any;
    await db.execute(`UPDATE tables SET zone_id = ? WHERE id = ?`, [z.insertId, tableId]);

    const res = await request(app)
      .patch(`/tables/${tableId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ zone_id: null });
    expect(res.status).toBe(200);
  });

  it('Tenant-Isolation: kann Tisch anderer Tenants nicht ändern', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [t2tbl] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'FremdTisch')`, [t2.insertId]) as any;

    const res = await request(app)
      .patch(`/tables/${t2tbl.insertId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Gehackt' });
    expect(res.status).toBe(404);
  });

  it('422 bei leerem Body', async () => {
    const res = await request(app).patch(`/tables/${tableId}`).set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(422);
  });
});

describe('DELETE /tables/:id', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('deaktiviert Tisch (soft delete)', async () => {
    const [t] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'Leer')`, [tenantId]) as any;
    const res = await request(app).delete(`/tables/${t.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);

    const [rows] = await db.execute(`SELECT is_active FROM tables WHERE id = ?`, [t.insertId]) as any;
    expect(rows[0].is_active).toBe(0);
  });

  it('404 bei bereits deaktiviertem Tisch', async () => {
    const [t] = await db.execute(`INSERT INTO tables (tenant_id, name, is_active) VALUES (?, 'Weg', FALSE)`, [tenantId]) as any;
    const res = await request(app).delete(`/tables/${t.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('Tenant-Isolation: kann Tisch anderer Tenants nicht löschen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const [t2tbl] = await db.execute(`INSERT INTO tables (tenant_id, name) VALUES (?, 'FremdTisch')`, [t2.insertId]) as any;

    const res = await request(app).delete(`/tables/${t2tbl.insertId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

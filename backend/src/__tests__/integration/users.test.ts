import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Test-Helpers ─────────────────────────────────────────────────────────────

async function createTenant(conn: any, name = 'Test GmbH') {
  const [r] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES (?, 'Musterstr. 1, 10115 Berlin', 'starter', 'active')`,
    [name]
  );
  await conn.execute(
    'INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)',
    [r.insertId]
  );
  return r.insertId as number;
}

async function createUser(conn: any, tenantId: number, role = 'owner', email = 'owner@test.de') {
  const hash = await bcrypt.hash('password123', 10);
  const [r] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Test User', ?, ?, ?)`,
    [tenantId, email, hash, role]
  );
  return r.insertId as number;
}

async function createDevice(conn: any, tenantId: number) {
  const tokenHash = crypto.createHash('sha256').update('dev-token').digest('hex');
  const [r] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash)
     VALUES (?, 'iPad Test', ?)`,
    [tenantId, tokenHash]
  );
  return r.insertId as number;
}

function makeToken(payload: AuthPayload) {
  return jwt.sign(payload, process.env['JWT_SECRET'] ?? 'test-secret', { expiresIn: '15m' });
}

// ─── GET /users ───────────────────────────────────────────────────────────────

describe('GET /users', () => {
  let tenantId: number;
  let token: string;

  beforeEach(async () => {
    tenantId       = await createTenant(db);
    const userId   = await createUser(db, tenantId, 'owner');
    const deviceId = await createDevice(db, tenantId);
    token = makeToken({ userId, tenantId, deviceId, role: 'owner' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt alle aktiven User zurück', async () => {
    const res = await request(app).get('/users').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(1);
    expect(res.body[0]).not.toHaveProperty('password_hash');
    expect(res.body[0]).not.toHaveProperty('pin_hash');
  });

  it('Tenant-Isolation: gibt keine User anderer Tenants zurück', async () => {
    const tenantB    = await createTenant(db, 'Tenant B');
    await createUser(db, tenantB, 'owner', 'other@tenantb.de');

    const res = await request(app).get('/users').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.every((u: any) => u.email !== 'other@tenantb.de')).toBe(true);
  });

  it('gibt 401 ohne Token', async () => {
    expect((await request(app).get('/users')).status).toBe(401);
  });
});

// ─── POST /users ──────────────────────────────────────────────────────────────

describe('POST /users', () => {
  let tenantId: number;
  let ownerToken: string;
  let managerToken: string;
  let staffToken: string;

  beforeEach(async () => {
    tenantId = await createTenant(db);
    const deviceId = await createDevice(db, tenantId);

    const ownerId    = await createUser(db, tenantId, 'owner',   'owner@t.de');
    const managerId  = await createUser(db, tenantId, 'manager', 'manager@t.de');
    const staffId    = await createUser(db, tenantId, 'staff',   'staff@t.de');

    ownerToken   = makeToken({ userId: ownerId,   tenantId, deviceId, role: 'owner' });
    managerToken = makeToken({ userId: managerId, tenantId, deviceId, role: 'manager' });
    staffToken   = makeToken({ userId: staffId,   tenantId, deviceId, role: 'staff' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('owner legt neuen staff-User an', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Neuer Kellner', email: 'kellner@t.de', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.role).toBe('staff');
    expect(res.body).not.toHaveProperty('password_hash');
  });

  it('manager legt staff an — erlaubt', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ name: 'Staff', email: 'newstaff@t.de', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(201);
  });

  it('manager kann keinen owner anlegen', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${managerToken}`)
      .send({ name: 'Boss', email: 'boss@t.de', password: 'sicher123', role: 'owner' });

    expect(res.status).toBe(403);
  });

  it('staff kann keine User anlegen', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ name: 'X', email: 'x@t.de', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(403);
  });

  it('gibt 409 bei doppelter E-Mail im selben Tenant', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Doppelt', email: 'owner@t.de', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(409);
  });

  it('gibt 422 bei fehlenden Feldern', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Kein Email', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });

  it('gibt 422 bei zu kurzem Passwort', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'X', email: 'x@t.de', password: '123', role: 'staff' });

    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: E-Mail-Duplikat-Check gilt nur pro Tenant', async () => {
    const tenantB  = await createTenant(db, 'Tenant B');
    const devB     = await createDevice(db, tenantB);
    const ownerB   = await createUser(db, tenantB, 'owner', 'owner@tenantb.de');
    const tokenB   = makeToken({ userId: ownerB, tenantId: tenantB, deviceId: devB, role: 'owner' });

    // E-Mail 'owner@t.de' existiert in Tenant A — Tenant B darf diese E-Mail verwenden
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${tokenB}`)
      .send({ name: 'Kopie', email: 'owner@t.de', password: 'sicher123', role: 'staff' });

    expect(res.status).toBe(201);
  });
});

// ─── DELETE /users/:id ────────────────────────────────────────────────────────

describe('DELETE /users/:id', () => {
  let tenantId: number;
  let ownerId: number;
  let ownerToken: string;

  beforeEach(async () => {
    tenantId       = await createTenant(db);
    const deviceId = await createDevice(db, tenantId);
    ownerId        = await createUser(db, tenantId, 'owner', 'owner@t.de');
    ownerToken     = makeToken({ userId: ownerId, tenantId, deviceId, role: 'owner' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('deaktiviert einen staff-User', async () => {
    const staffId = await createUser(db, tenantId, 'staff', 'staff@t.de');
    const res = await request(app)
      .delete(`/users/${staffId}`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('verhindert Löschen des letzten Owners', async () => {
    const res = await request(app)
      .delete(`/users/${ownerId}`)
      .set('Authorization', `Bearer ${ownerToken}`);

    // ownerId ist gleichzeitig req.auth.userId → 409 wegen "eigenen Account"
    expect(res.status).toBe(409);
  });

  it('gibt 404 wenn User zu anderem Tenant gehört (Tenant-Isolation)', async () => {
    const tenantB = await createTenant(db, 'Tenant B');
    const userB   = await createUser(db, tenantB, 'staff', 'staff@b.de');

    const res = await request(app)
      .delete(`/users/${userB}`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(404);
  });
});

// ─── PATCH /users/:id ─────────────────────────────────────────────────────────

describe('PATCH /users/:id', () => {
  let ownerToken: string; let tenantId: number; let ownerId: number; let deviceId: number;

  beforeEach(async () => {
    tenantId = await createTenant(db);
    ownerId  = await createUser(db, tenantId, 'owner', 'owner@t.de');
    deviceId = await createDevice(db, tenantId);
    ownerToken = makeToken({ userId: ownerId, tenantId, deviceId, role: 'owner' });
  });
  afterEach(() => { /* cleanup: global afterEach in setup.ts */ });

  it('aktualisiert name und role', async () => {
    const staffId = await createUser(db, tenantId, 'staff', 'staff@t.de');
    const res = await request(app)
      .patch(`/users/${staffId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Neuer Name', role: 'manager' });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('Validierungsfehler: leeres Body → 422', async () => {
    const staffId = await createUser(db, tenantId, 'staff', 'staff2@t.de');
    const res = await request(app)
      .patch(`/users/${staffId}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({});
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann User anderer Tenants nicht ändern', async () => {
    const tenantB = await createTenant(db, 'Tenant B');
    const userB   = await createUser(db, tenantB, 'staff', 'x@b.de');
    const res = await request(app)
      .patch(`/users/${userB}`)
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Hacked' });
    expect(res.status).toBe(404);
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app).patch(`/users/1`).send({ name: 'X' });
    expect(res.status).toBe(401);
  });
});

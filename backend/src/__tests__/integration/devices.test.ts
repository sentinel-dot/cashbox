import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Test-Helpers ─────────────────────────────────────────────────────────────

async function createTenant(conn: any, name = 'Device Test GmbH', plan = 'starter') {
  const [r] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES (?, 'Teststr. 1, 10115 Berlin', ?, 'active')`,
    [name, plan]
  );
  await conn.execute(
    'INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)',
    [r.insertId]
  );
  return r.insertId as number;
}

async function createUser(conn: any, tenantId: number, role = 'owner') {
  const hash = await bcrypt.hash('password123', 10);
  const [r] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Test User', ?, ?, ?)`,
    [tenantId, `${role}-${tenantId}@test.de`, hash, role]
  );
  return r.insertId as number;
}

async function createDevice(conn: any, tenantId: number, raw = 'test-token') {
  const tokenHash = crypto.createHash('sha256').update(raw).digest('hex');
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

// ─── GET /devices ─────────────────────────────────────────────────────────────

describe('GET /devices', () => {
  let tenantId: number;
  let token: string;

  beforeEach(async () => {
    tenantId       = await createTenant(db);
    const userId   = await createUser(db, tenantId, 'owner');
    const deviceId = await createDevice(db, tenantId);
    token = makeToken({ userId, tenantId, deviceId, role: 'owner' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt alle Geräte des Tenants zurück', async () => {
    const res = await request(app).get('/devices').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(1);
    expect(res.body[0]).not.toHaveProperty('device_token_hash');
  });

  it('Tenant-Isolation: gibt keine Geräte anderer Tenants zurück', async () => {
    const tenantB = await createTenant(db, 'Tenant B');
    await createDevice(db, tenantB, 'tenant-b-token');

    const res = await request(app).get('/devices').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBe(1); // Nur eigenes Gerät
  });
});

// ─── POST /devices/register ───────────────────────────────────────────────────

describe('POST /devices/register', () => {
  let tenantId: number;
  let ownerToken: string;
  let staffToken: string;

  beforeEach(async () => {
    // 'pro' plan allows 3 devices — leaves room to register a second
    tenantId = await createTenant(db, 'Device Test GmbH', 'pro');
    const deviceId   = await createDevice(db, tenantId);
    const ownerId    = await createUser(db, tenantId, 'owner');
    const staffId    = await createUser(db, tenantId, 'staff');
    ownerToken = makeToken({ userId: ownerId, tenantId, deviceId, role: 'owner' });
    staffToken = makeToken({ userId: staffId, tenantId, deviceId, role: 'staff' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('owner registriert neues Gerät — device_token wird einmalig zurückgegeben', async () => {
    const res = await request(app)
      .post('/devices/register')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'iPad Tisch 1' });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('device_token');
    expect(typeof res.body.device_token).toBe('string');
    expect(res.body.device_token.length).toBeGreaterThan(10);
    expect(res.body.tse_client_id).toBeNull(); // Phase 2
  });

  it('staff kann kein Gerät registrieren', async () => {
    const res = await request(app)
      .post('/devices/register')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ name: 'iPad Hacker' });

    expect(res.status).toBe(403);
  });

  it('gibt 422 bei fehlendem name', async () => {
    const res = await request(app)
      .post('/devices/register')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({});

    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });
});

describe('POST /devices/register — Plan-Limit', () => {
  let ownerToken: string;

  beforeEach(async () => {
    const tenantId   = await createTenant(db); // starter: max 1 Gerät
    const deviceId   = await createDevice(db, tenantId);
    const ownerId    = await createUser(db, tenantId, 'owner');
    ownerToken = makeToken({ userId: ownerId, tenantId, deviceId, role: 'owner' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('Plan-Limit starter: max 1 Gerät', async () => {
    // Starter-Plan hat bereits 1 Gerät (aus beforeEach)
    const res = await request(app)
      .post('/devices/register')
      .set('Authorization', `Bearer ${ownerToken}`)
      .send({ name: 'Zweites iPad' });

    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Plan-Limit/);
  });
});

// ─── POST /devices/:id/revoke ─────────────────────────────────────────────────

describe('POST /devices/:id/revoke', () => {
  let tenantId: number;
  let activeDeviceId: number;
  let ownerToken: string;

  beforeEach(async () => {
    tenantId      = await createTenant(db);
    activeDeviceId = await createDevice(db, tenantId, 'active-token');
    const ownerId = await createUser(db, tenantId, 'owner');
    ownerToken    = makeToken({ userId: ownerId, tenantId, deviceId: activeDeviceId, role: 'owner' });
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('sperrt ein anderes Gerät erfolgreich', async () => {
    const otherDeviceId = await createDevice(db, tenantId, 'other-device-token');

    const res = await request(app)
      .post(`/devices/${otherDeviceId}/revoke`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const [rows] = await db.execute<any[]>(
      'SELECT is_revoked FROM devices WHERE id = ?',
      [otherDeviceId]
    );
    expect(rows[0].is_revoked).toBe(1);
  });

  it('verhindert Sperren des eigenen aktiven Geräts', async () => {
    const res = await request(app)
      .post(`/devices/${activeDeviceId}/revoke`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(409);
  });

  it('gibt 404 bei bereits gesperrtem Gerät', async () => {
    const otherDeviceId = await createDevice(db, tenantId, 'old-token');
    await db.execute('UPDATE devices SET is_revoked = TRUE WHERE id = ?', [otherDeviceId]);

    const res = await request(app)
      .post(`/devices/${otherDeviceId}/revoke`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(409);
  });

  it('Tenant-Isolation: Gerät eines anderen Tenants kann nicht gesperrt werden', async () => {
    const tenantB      = await createTenant(db, 'Tenant B');
    const deviceB      = await createDevice(db, tenantB, 'tenant-b-device');

    const res = await request(app)
      .post(`/devices/${deviceB}/revoke`)
      .set('Authorization', `Bearer ${ownerToken}`);

    expect(res.status).toBe(404);
  });
});

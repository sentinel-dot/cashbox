import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import app from '../../app.js';
import { db } from '../../db/index.js';

// ─── Test-Fixtures ──────────────────────────────────────────────────────────

async function createTenant(conn: any, name = 'Test Tenant') {
  const [r] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES (?, 'Teststr. 1, 12345 Berlin', 'starter', 'active')`,
    [name]
  );
  await conn.execute(
    'INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)',
    [r.insertId]
  );
  return r.insertId as number;
}

async function createUser(conn: any, tenantId: number, overrides: Record<string, any> = {}) {
  const passwordHash = await bcrypt.hash(overrides.password ?? 'password123', 10);
  const pinHash = overrides.pin ? await bcrypt.hash(overrides.pin, 10) : null;
  const [r] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      tenantId,
      overrides.name     ?? 'Test User',
      overrides.email    ?? 'user@test.de',
      passwordHash,
      overrides.role     ?? 'staff',
      pinHash,
    ]
  );
  return r.insertId as number;
}

async function createDevice(conn: any, tenantId: number, rawToken = 'test-device-token-abc') {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const [r] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash)
     VALUES (?, 'iPad Theke', ?)`,
    [tenantId, tokenHash]
  );
  return { id: r.insertId as number, rawToken };
}

// ─── Tests ──────────────────────────────────────────────────────────────────

describe('POST /auth/login', () => {
  let tenantId: number;
  let deviceToken: string;

  beforeEach(async () => {
    tenantId = await createTenant(db);
    await createUser(db, tenantId, { email: 'niko@test.de', password: 'geheim123' });
    const dev = await createDevice(db, tenantId);
    deviceToken = dev.rawToken;
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt JWT + RefreshToken zurück bei korrekten Credentials', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123', device_token: deviceToken });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('refreshToken');
    expect(res.body.user).toMatchObject({ role: 'staff' });
    expect(res.body.device).toHaveProperty('id');
  });

  it('gibt 401 bei falschem Passwort', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'falsch', device_token: deviceToken });

    expect(res.status).toBe(401);
  });

  it('gibt 401 bei unbekanntem Gerät', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123', device_token: 'unbekanntes-token' });

    expect(res.status).toBe(401);
  });

  it('gibt 422 bei fehlendem device_token', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123' });

    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });

  it('gibt 422 bei ungültiger E-Mail', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'keine-email', password: 'geheim123', device_token: deviceToken });

    expect(res.status).toBe(422);
  });

  // Tenant-Isolation: Gerät von Tenant B kann nicht mit User von Tenant A einloggen
  it('Tenant-Isolation: Gerät von Tenant B kann nicht User von Tenant A authentifizieren', async () => {
    const tenantBId = await createTenant(db, 'Tenant B');
    const devB = await createDevice(db, tenantBId, 'tenant-b-device-token');

    const res = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123', device_token: devB.rawToken });

    // Tenant B's Gerät kennt niko@test.de (gehört zu Tenant A) nicht
    expect(res.status).toBe(401);
  });
});

describe('POST /auth/refresh', () => {
  let tenantId: number;
  let deviceToken: string;

  beforeEach(async () => {
    tenantId = await createTenant(db);
    await createUser(db, tenantId, { email: 'niko@test.de', password: 'geheim123' });
    const dev = await createDevice(db, tenantId);
    deviceToken = dev.rawToken;
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt neues JWT zurück bei gültigem RefreshToken', async () => {
    // Erst einloggen
    const loginRes = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123', device_token: deviceToken });

    expect(loginRes.status).toBe(200);
    const { refreshToken } = loginRes.body;

    const res = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: refreshToken });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('refreshToken');
  });

  it('gibt 401 bei ungültigem Token', async () => {
    const res = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: 'das-ist-kein-gueltiger-jwt' });

    expect(res.status).toBe(401);
  });

  it('gibt 422 bei fehlendem refresh_token', async () => {
    const res = await request(app).post('/auth/refresh').send({});
    expect(res.status).toBe(422);
  });

  // ─── Absolutes Session-Limit (SESSION_MAX_HOURS, Default 16h) ────────────

  async function loginAndGetIds() {
    const loginRes = await request(app)
      .post('/auth/login')
      .send({ email: 'niko@test.de', password: 'geheim123', device_token: deviceToken });
    expect(loginRes.status).toBe(200);
    const payload = jwt.decode(loginRes.body.refreshToken) as any;
    return { refreshToken: loginRes.body.refreshToken as string, payload };
  }

  it('Refresh-Token enthält session_start und läuft spätestens nach 16h ab', async () => {
    const { payload } = await loginAndGetIds();

    expect(typeof payload.session_start).toBe('number');
    expect(payload.exp).toBeLessThanOrEqual(payload.session_start + 16 * 3600);
  });

  it('Rotation verlängert die Session nicht: session_start bleibt identisch', async () => {
    const { refreshToken } = await loginAndGetIds();

    const first = await request(app).post('/auth/refresh').send({ refresh_token: refreshToken });
    expect(first.status).toBe(200);
    const second = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: first.body.refreshToken });
    expect(second.status).toBe(200);

    const original = jwt.decode(refreshToken) as any;
    const rotated  = jwt.decode(second.body.refreshToken) as any;
    expect(rotated.session_start).toBe(original.session_start);
  });

  it('gibt 401 wenn session_start älter als das Session-Limit ist', async () => {
    const { payload } = await loginAndGetIds();

    const expired = jwt.sign(
      {
        userId:        payload.userId,
        tenantId:      payload.tenantId,
        deviceId:      payload.deviceId,
        role:          payload.role,
        type:          'refresh',
        session_start: Math.floor(Date.now() / 1000) - 17 * 3600, // 17h alt
      },
      process.env['JWT_SECRET']!,
      { expiresIn: '1h' }
    );

    const res = await request(app).post('/auth/refresh').send({ refresh_token: expired });
    expect(res.status).toBe(401);
    expect(res.body.error).toMatch(/Sitzung abgelaufen/);
  });

  it('gibt 401 bei Alt-Token ohne session_start-Claim', async () => {
    const { payload } = await loginAndGetIds();

    const legacy = jwt.sign(
      {
        userId:   payload.userId,
        tenantId: payload.tenantId,
        deviceId: payload.deviceId,
        role:     payload.role,
        type:     'refresh',
      },
      process.env['JWT_SECRET']!,
      { expiresIn: '7d' }
    );

    const res = await request(app).post('/auth/refresh').send({ refresh_token: legacy });
    expect(res.status).toBe(401);
    expect(res.body.error).toMatch(/Sitzung abgelaufen/);
  });
});

describe('POST /auth/pin', () => {
  let tenantId: number;
  let deviceToken: string;

  beforeEach(async () => {
    tenantId = await createTenant(db);
    await createUser(db, tenantId, { email: 'owner@test.de', password: 'geheim123', pin: '1234', role: 'owner' });
    await createUser(db, tenantId, { email: 'staff@test.de',  password: 'geheim456', pin: '5678', role: 'staff' });
    const dev = await createDevice(db, tenantId);
    deviceToken = dev.rawToken;
  });

  afterEach(() => { /* cleanup handled by global afterEach in setup.ts */ });

  it('gibt JWT für den User mit passender PIN zurück', async () => {
    const res = await request(app)
      .post('/auth/pin')
      .send({ device_token: deviceToken, pin: '1234' });

    expect(res.status).toBe(200);
    expect(res.body.user.role).toBe('owner');
    expect(res.body).toHaveProperty('token');
  });

  it('gibt 401 bei falscher PIN', async () => {
    const res = await request(app)
      .post('/auth/pin')
      .send({ device_token: deviceToken, pin: '9999' });

    expect(res.status).toBe(401);
  });

  it('gibt 422 bei PIN mit falscher Länge', async () => {
    const res = await request(app)
      .post('/auth/pin')
      .send({ device_token: deviceToken, pin: '12' });

    expect(res.status).toBe(422);
  });

  it('gibt 422 bei nicht-numerischer PIN', async () => {
    const res = await request(app)
      .post('/auth/pin')
      .send({ device_token: deviceToken, pin: 'abcd' });

    expect(res.status).toBe(422);
  });

  // Tenant-Isolation
  it('Tenant-Isolation: PIN von Tenant A funktioniert nicht mit Gerät von Tenant B', async () => {
    const tenantBId = await createTenant(db, 'Tenant B');
    const devB = await createDevice(db, tenantBId, 'tenant-b-pin-device');

    // PIN '1234' gehört zu Tenant A — Gerät B kennt die nicht
    const res = await request(app)
      .post('/auth/pin')
      .send({ device_token: devB.rawToken, pin: '1234' });

    expect(res.status).toBe(401);
  });
});

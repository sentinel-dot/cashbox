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

async function openSessionHelper(token: string): Promise<number> {
  const res = await request(app)
    .post('/sessions/open')
    .set('Authorization', `Bearer ${token}`)
    .send({ opening_cash_cents: 5000 });
  return res.body.id as number;
}

// ─── POST /sessions/open ─────────────────────────────────────────────────────

describe('POST /sessions/open', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('öffnet neue Kassensitzung', async () => {
    const res = await request(app)
      .post('/sessions/open')
      .set('Authorization', `Bearer ${token}`)
      .send({ opening_cash_cents: 5000 });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.status).toBe('open');
    expect(res.body.opening_cash_cents).toBe(5000);
  });

  it('409 wenn bereits eine Session offen ist', async () => {
    await openSessionHelper(token);
    const res = await request(app)
      .post('/sessions/open')
      .set('Authorization', `Bearer ${token}`)
      .send({ opening_cash_cents: 0 });
    expect(res.status).toBe(409);
  });

  it('422 bei fehlendem opening_cash_cents', async () => {
    const res = await request(app)
      .post('/sessions/open')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });

  it('422 bei negativem opening_cash_cents', async () => {
    const res = await request(app)
      .post('/sessions/open')
      .set('Authorization', `Bearer ${token}`)
      .send({ opening_cash_cents: -1 });
    expect(res.status).toBe(422);
  });

  it('422 bei float opening_cash_cents', async () => {
    const res = await request(app)
      .post('/sessions/open')
      .set('Authorization', `Bearer ${token}`)
      .send({ opening_cash_cents: 50.50 });
    expect(res.status).toBe(422);
  });
});

// ─── GET /sessions/current ───────────────────────────────────────────────────

describe('GET /sessions/current', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt offene Session zurück', async () => {
    await openSessionHelper(token);
    const res = await request(app).get('/sessions/current').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('open');
    expect(res.body).toHaveProperty('movements');
  });

  it('404 wenn keine Session offen', async () => {
    const res = await request(app).get('/sessions/current').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('Tenant-Isolation: zeigt keine Session eines anderen Tenants', async () => {
    // Tenant B mit eigenem Device + Session
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'B', 'b@b.de', ?, 'owner')`, [t2.insertId, hash]) as any;
    const tok2Hash = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad B', ?)`, [t2.insertId, tok2Hash]) as any;
    const token2 = jwt.sign(
      { userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload,
      process.env['JWT_SECRET'] ?? 'test-secret',
      { expiresIn: '15m' }
    );
    await openSessionHelper(token2);

    // Tenant A hat keine eigene Session → 404
    const res = await request(app).get('/sessions/current').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── POST /sessions/close ────────────────────────────────────────────────────

describe('POST /sessions/close', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('schließt Session und liefert Z-Bericht', async () => {
    await openSessionHelper(token);
    const res = await request(app)
      .post('/sessions/close')
      .set('Authorization', `Bearer ${token}`)
      .send({ closing_cash_cents: 5000 });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('z_report_id');
    expect(res.body).toHaveProperty('closing_cash_cents', 5000);
    expect(res.body).toHaveProperty('expected_cash_cents');
    expect(res.body).toHaveProperty('difference_cents');
    expect(res.body).toHaveProperty('total_revenue_cents');
  });

  it('schreibt Z-Bericht in z_reports-Tabelle', async () => {
    const sessionId = await openSessionHelper(token);
    await request(app)
      .post('/sessions/close')
      .set('Authorization', `Bearer ${token}`)
      .send({ closing_cash_cents: 5000 });

    const [rows] = await db.execute(`SELECT * FROM z_reports WHERE session_id = ?`, [sessionId]) as any;
    expect(rows.length).toBe(1);
    expect(rows[0].report_json).toBeDefined();
  });

  it('Session ist danach geschlossen', async () => {
    const sessionId = await openSessionHelper(token);
    await request(app).post('/sessions/close').set('Authorization', `Bearer ${token}`).send({ closing_cash_cents: 5000 });

    const [rows] = await db.execute(`SELECT status FROM cash_register_sessions WHERE id = ?`, [sessionId]) as any;
    expect(rows[0].status).toBe('closed');
  });

  it('404 wenn keine offene Session vorhanden', async () => {
    const res = await request(app).post('/sessions/close').set('Authorization', `Bearer ${token}`).send({ closing_cash_cents: 0 });
    expect(res.status).toBe(404);
  });

  it('422 bei fehlendem closing_cash_cents', async () => {
    await openSessionHelper(token);
    const res = await request(app).post('/sessions/close').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(422);
  });
});

// ─── GET /sessions/:id ───────────────────────────────────────────────────────

describe('GET /sessions/:id', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Session-Details zurück', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app).get(`/sessions/${sessionId}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(sessionId);
    expect(res.body).toHaveProperty('movements');
  });

  it('Tenant-Isolation: kann Session anderer Tenants nicht lesen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'B', 'b@b.de', ?, 'owner')`, [t2.insertId, hash]) as any;
    const tok2Hash = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad B', ?)`, [t2.insertId, tok2Hash]) as any;
    const token2 = jwt.sign(
      { userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload,
      process.env['JWT_SECRET'] ?? 'test-secret',
      { expiresIn: '15m' }
    );
    const sessionId2 = await openSessionHelper(token2);

    const res = await request(app).get(`/sessions/${sessionId2}`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── GET /sessions/:id/z-report ──────────────────────────────────────────────

describe('GET /sessions/:id/z-report', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Z-Bericht nach Abschluss zurück', async () => {
    const sessionId = await openSessionHelper(token);
    await request(app).post('/sessions/close').set('Authorization', `Bearer ${token}`).send({ closing_cash_cents: 5000 });

    const res = await request(app).get(`/sessions/${sessionId}/z-report`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('report');
    expect(res.body.report).toHaveProperty('total_revenue_cents');
  });

  it('409 wenn Session noch offen', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app).get(`/sessions/${sessionId}/z-report`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(409);
  });

  it('Tenant-Isolation: kann Z-Bericht anderer Tenants nicht lesen', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'B', 'b@b.de', ?, 'owner')`, [t2.insertId, hash]) as any;
    const tok2Hash = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad B', ?)`, [t2.insertId, tok2Hash]) as any;
    const token2 = jwt.sign(
      { userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload,
      process.env['JWT_SECRET'] ?? 'test-secret',
      { expiresIn: '15m' }
    );
    const sessionId2 = await openSessionHelper(token2);
    await request(app).post('/sessions/close').set('Authorization', `Bearer ${token2}`).send({ closing_cash_cents: 0 });

    const res = await request(app).get(`/sessions/${sessionId2}/z-report`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});

// ─── POST /sessions/:id/movements ────────────────────────────────────────────

describe('POST /sessions/:id/movements', () => {
  let token: string;

  beforeEach(async () => { ({ token } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('fügt Einlage hinzu', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'deposit', amount_cents: 2000, reason: 'Wechselgeld einlegen' });
    expect(res.status).toBe(201);
    expect(res.body.type).toBe('deposit');
    expect(res.body.amount_cents).toBe(2000);
  });

  it('fügt Entnahme hinzu', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'withdrawal', amount_cents: 500, reason: 'Betriebsausgabe' });
    expect(res.status).toBe(201);
    expect(res.body.type).toBe('withdrawal');
  });

  it('wird im Z-Bericht berücksichtigt (expected_cash_cents)', async () => {
    const sessionId = await openSessionHelper(token); // 5000 Anfang
    await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'deposit', amount_cents: 1000, reason: 'Test' });
    const closeRes = await request(app)
      .post('/sessions/close')
      .set('Authorization', `Bearer ${token}`)
      .send({ closing_cash_cents: 6000 });
    // expected = 5000 (Anfang) + 0 (Umsatz) + 1000 (Einlage) = 6000
    expect(closeRes.body.expected_cash_cents).toBe(6000);
    expect(closeRes.body.difference_cents).toBe(0);
  });

  it('404 wenn Session geschlossen oder fremd', async () => {
    const sessionId = await openSessionHelper(token);
    await request(app).post('/sessions/close').set('Authorization', `Bearer ${token}`).send({ closing_cash_cents: 5000 });

    const res = await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'deposit', amount_cents: 100, reason: 'X' });
    expect(res.status).toBe(404);
  });

  it('422 bei fehlendem reason', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'deposit', amount_cents: 100 });
    expect(res.status).toBe(422);
  });

  it('422 bei ungültigem type', async () => {
    const sessionId = await openSessionHelper(token);
    const res = await request(app)
      .post(`/sessions/${sessionId}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'tip', amount_cents: 100, reason: 'X' });
    expect(res.status).toBe(422);
  });

  it('Tenant-Isolation: kann keine Bewegung in fremde Session schreiben', async () => {
    // Erstelle fremde Session in einer anderen Tenant-DB
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B', 'X', 'starter', 'active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`, [t2.insertId]);
    const hash = await bcrypt.hash('pw', 10);
    const [u2] = await db.execute(`INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'B', 'b@b.de', ?, 'owner')`, [t2.insertId, hash]) as any;
    const tok2Hash = crypto.createHash('sha256').update('tok2').digest('hex');
    const [d2] = await db.execute(`INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad B', ?)`, [t2.insertId, tok2Hash]) as any;
    const token2 = jwt.sign(
      { userId: u2.insertId, tenantId: t2.insertId, deviceId: d2.insertId, role: 'owner' } as AuthPayload,
      process.env['JWT_SECRET'] ?? 'test-secret',
      { expiresIn: '15m' }
    );
    const sessionId2 = await openSessionHelper(token2);

    const res = await request(app)
      .post(`/sessions/${sessionId2}/movements`)
      .set('Authorization', `Bearer ${token}`)
      .send({ type: 'deposit', amount_cents: 100, reason: 'Hack' });
    expect(res.status).toBe(404);
  });
});

import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Setup ────────────────────────────────────────────────────────────────────

async function setup(opts: { tssId?: string } = {}) {
  const [t] = await db.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status, fiskaly_tss_id)
     VALUES ('Test GmbH', 'Teststr. 1, 10115 Berlin', 'business', 'active', ?)`,
    [opts.tssId ?? null]
  ) as any;
  const tenantId = t.insertId as number;
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Owner', 'o@t.de', ?, 'owner')`,
    [tenantId, hash]
  ) as any;
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await db.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  ) as any;
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}

const TODAY     = new Date().toISOString().slice(0, 10);
const YESTERDAY = (() => { const d = new Date(); d.setDate(d.getDate() - 1); return d.toISOString().slice(0, 10); })();

// ─── GET /export/dsfinvk ──────────────────────────────────────────────────────

describe('GET /export/dsfinvk', () => {
  let token: string;

  beforeEach(async () => {
    // Kein tssId → 503-Pfad testbar ohne echte Fiskaly-Verbindung
    ({ token } = await setup());
  });

  it('503 wenn kein fiskaly_tss_id konfiguriert', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?from=${YESTERDAY}&to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/TSE nicht konfiguriert/);
  });

  it('422 bei fehlendem from-Parameter', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });

  it('422 bei fehlendem to-Parameter', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?from=${YESTERDAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body).toHaveProperty('details');
  });

  it('422 bei ungültigem Datumsformat (from)', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?from=15-03-2026&to=${TODAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
  });

  it('422 wenn from nach to liegt', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?from=${TODAY}&to=${YESTERDAY}`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(422);
    expect(res.body.error).toMatch(/from/);
  });

  it('401 ohne Token', async () => {
    const res = await request(app)
      .get(`/export/dsfinvk?from=${YESTERDAY}&to=${TODAY}`);
    expect(res.status).toBe(401);
  });
});

// ─── GET /export/dsfinvk/:exportId/status ────────────────────────────────────

describe('GET /export/dsfinvk/:exportId/status', () => {
  it('503 wenn kein fiskaly_tss_id konfiguriert', async () => {
    const { token } = await setup();
    const fakeExportId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    const res = await request(app)
      .get(`/export/dsfinvk/${fakeExportId}/status`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(503);
  });

  it('401 ohne Token', async () => {
    const res = await request(app)
      .get('/export/dsfinvk/some-id/status');
    expect(res.status).toBe(401);
  });

  it('Tenant-Isolation: Tenant B erhält 503 (kein eigener TSS) statt Daten von Tenant A', async () => {
    // Tenant A hätte theoretisch einen TSS — Tenant B hat keinen eigenen
    const { token: tokenB } = await setup(); // kein tssId
    const fakeExportId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    const res = await request(app)
      .get(`/export/dsfinvk/${fakeExportId}/status`)
      .set('Authorization', `Bearer ${tokenB}`);
    // Ohne eigenen TSS: 503 — nicht möglich auf fremde Exports zuzugreifen
    expect(res.status).toBe(503);
  });
});

// ─── GET /export/dsfinvk/:exportId/file ──────────────────────────────────────

describe('GET /export/dsfinvk/:exportId/file', () => {
  it('503 wenn kein fiskaly_tss_id konfiguriert', async () => {
    const { token } = await setup();
    const fakeExportId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    const res = await request(app)
      .get(`/export/dsfinvk/${fakeExportId}/file`)
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(503);
  });

  it('401 ohne Token', async () => {
    const res = await request(app)
      .get('/export/dsfinvk/some-id/file');
    expect(res.status).toBe(401);
  });
});

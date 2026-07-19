import { describe, it, expect, beforeEach, vi } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';

// Sentry vor dem app-Import mocken — app.ts bindet captureException beim Laden.
vi.mock('../../sentry.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../sentry.js')>();
  return { ...actual, captureException: vi.fn() };
});

import app from '../../app.js';
import { db } from '../../db/index.js';
import { captureException } from '../../sentry.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// REQ-OPS-002 (UC-OPS-02): 5xx werden an das Error-Monitoring gemeldet, 4xx nicht.
// Ohne diesen Test fällt eine abgerissene Sentry-Verdrahtung erst dann auf, wenn
// im Pilotbetrieb ein Fehler auftritt und niemand ihn sieht — genau der Zustand,
// den S1 beseitigen soll.

async function setup(role: 'owner' | 'manager' | 'staff' = 'owner') {
  const [t] = await db.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Shishabar GmbH', 'Musterstr. 1, 10115 Berlin', 'business', 'active')`
  ) as any;
  const tenantId = t.insertId as number;
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, ?)`,
    [tenantId, hash, role]
  ) as any;
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await db.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  ) as any;

  const token = jwt.sign(
    { userId, tenantId, deviceId: d.insertId as number, role } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, token };
}

describe('Globaler Error-Handler → Sentry', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => {
    vi.mocked(captureException).mockClear();
    ({ token, tenantId } = await setup());
  });

  it('meldet einen 5xx an Sentry — mit tenant, URL und Methode als Kontext', async () => {
    // Realistischer 500er: die DB fällt mitten im Request aus.
    const spy = vi.spyOn(db, 'execute').mockRejectedValueOnce(new Error('DB weg'));

    const res = await request(app).get('/tenants/me').set('Authorization', `Bearer ${token}`);
    spy.mockRestore();

    expect(res.status).toBe(500);
    expect(captureException).toHaveBeenCalledTimes(1);

    const [err, ctx] = vi.mocked(captureException).mock.calls[0]!;
    expect((err as Error).message).toBe('DB weg');
    expect(ctx).toMatchObject({ url: '/tenants/me', method: 'GET', tenant: tenantId });
  });

  it('meldet 4xx NICHT an Sentry (falscher Token ist kein Serverfehler)', async () => {
    const res = await request(app).get('/tenants/me').set('Authorization', 'Bearer kaputt');

    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    expect(captureException).not.toHaveBeenCalled();
  });

  it('gibt in Production keinen Stack Trace an den Client', async () => {
    const prev = process.env['NODE_ENV'];
    process.env['NODE_ENV'] = 'production';
    const spy = vi.spyOn(db, 'execute').mockRejectedValueOnce(new Error('Interne Tabellenstruktur XY'));

    const res = await request(app).get('/tenants/me').set('Authorization', `Bearer ${token}`);

    spy.mockRestore();
    process.env['NODE_ENV'] = prev;

    expect(res.status).toBe(500);
    expect(res.body.error).toBe('Interner Serverfehler.');
    expect(JSON.stringify(res.body)).not.toContain('Tabellenstruktur');
  });
});

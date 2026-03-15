import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function setup(conn: any, role: 'owner' | 'manager' | 'staff' = 'owner') {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, vat_id, tax_number, plan, subscription_status)
     VALUES ('Shishabar GmbH', 'Musterstr. 1, 10115 Berlin', 'DE123456789', '12/345/67890', 'business', 'active')`
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, ?)`,
    [tenantId, hash, role]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}

// ─── GET /tenants/me ──────────────────────────────────────────────────────────

describe('GET /tenants/me', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db)); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('gibt Tenant-Stammdaten zurück', async () => {
    const res = await request(app).get('/tenants/me').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(tenantId);
    expect(res.body.name).toBe('Shishabar GmbH');
    expect(res.body.address).toBe('Musterstr. 1, 10115 Berlin');
    expect(res.body.vat_id).toBe('DE123456789');
    expect(res.body.tax_number).toBe('12/345/67890');
  });

  it('enthält keine sensiblen Felder (kein stripe_customer_id etc.)', async () => {
    const res = await request(app).get('/tenants/me').set('Authorization', `Bearer ${token}`);
    expect(res.body).not.toHaveProperty('stripe_customer_id');
    expect(res.body).not.toHaveProperty('fiskaly_tss_id');
  });

  it('Tenant-Isolation: gibt nur eigenen Tenant zurück', async () => {
    const [t2] = await db.execute(`INSERT INTO tenants (name, address, plan, subscription_status) VALUES ('B','X','starter','active')`) as any;
    await db.execute(`INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?,0)`, [t2.insertId]);

    // Tenant A sieht nur sich selbst
    const res = await request(app).get('/tenants/me').set('Authorization', `Bearer ${token}`);
    expect(res.body.id).toBe(tenantId);
    expect(res.body.name).toBe('Shishabar GmbH');
  });
});

// ─── PATCH /tenants/me ───────────────────────────────────────────────────────

describe('PATCH /tenants/me', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => { ({ token, tenantId } = await setup(db, 'owner')); });
  afterEach(() => { /* cleanup in setup.ts */ });

  it('aktualisiert Adresse (Bon-Pflichtfeld)', async () => {
    const res = await request(app)
      .patch('/tenants/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ address: 'Neue Str. 5, 10117 Berlin' });
    expect(res.status).toBe(200);

    const [rows] = await db.execute(`SELECT address FROM tenants WHERE id = ?`, [tenantId]) as any;
    expect(rows[0].address).toBe('Neue Str. 5, 10117 Berlin');
  });

  it('aktualisiert USt-IdNr. und Steuernummer', async () => {
    const res = await request(app)
      .patch('/tenants/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ vat_id: 'DE999999999', tax_number: '99/999/99999' });
    expect(res.status).toBe(200);

    const [rows] = await db.execute(`SELECT vat_id, tax_number FROM tenants WHERE id = ?`, [tenantId]) as any;
    expect(rows[0].vat_id).toBe('DE999999999');
    expect(rows[0].tax_number).toBe('99/999/99999');
  });

  it('setzt vat_id auf null', async () => {
    const res = await request(app)
      .patch('/tenants/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ vat_id: null });
    expect(res.status).toBe(200);

    const [rows] = await db.execute(`SELECT vat_id FROM tenants WHERE id = ?`, [tenantId]) as any;
    expect(rows[0].vat_id).toBeNull();
  });

  it('schreibt audit_log', async () => {
    await request(app).patch('/tenants/me').set('Authorization', `Bearer ${token}`).send({ name: 'Neuer Name GmbH' });

    const [rows] = await db.execute(
      `SELECT id FROM audit_log WHERE action = 'tenant.updated' AND entity_id = ?`, [tenantId]
    ) as any;
    expect(rows.length).toBe(1);
  });

  it('403 für staff-Benutzer', async () => {
    const { token: staffToken } = await setup(db, 'staff');
    const res = await request(app)
      .patch('/tenants/me')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ name: 'Hack' });
    expect(res.status).toBe(403);
  });

  it('422 bei leerem Body', async () => {
    const res = await request(app)
      .patch('/tenants/me')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(422);
  });
});

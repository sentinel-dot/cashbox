import { Request, Response } from 'express';
import crypto from 'crypto';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const registerDeviceSchema = z.object({
  name: z.string().min(1).max(255),   // z.B. "iPad Theke", "iPad Tisch 1"
});

// revoke hat keinen Body — device_id kommt aus URL-Param

// ─── Handler ────────────────────────────────────────────────────────────────

export async function listDevices(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const [rows] = await db.execute<any[]>(
    `SELECT id, name, tse_client_id, is_revoked, last_seen_at, created_at
     FROM devices
     WHERE tenant_id = ?
     ORDER BY created_at ASC`,
    [tenantId]
  );

  res.json(rows);
}

export async function registerDevice(req: Request, res: Response): Promise<void> {
  // Nur owner darf Geräte registrieren
  if (req.auth!.role !== 'owner') {
    res.status(403).json({ error: 'Nur Owner dürfen Geräte registrieren.' });
    return;
  }

  const tenantId = req.auth!.tenantId;
  const { name } = req.body as z.infer<typeof registerDeviceSchema>;

  // Device-Token: UUID v4 als Klartext — wird NUR hier einmalig zurückgegeben
  // In DB: nur SHA-256-Hash gespeichert (kein Klartext)
  const rawToken   = crypto.randomUUID();
  const tokenHash  = crypto.createHash('sha256').update(rawToken).digest('hex');

  const [result] = await db.execute<any>(
    `INSERT INTO devices (tenant_id, name, device_token_hash, tse_client_id)
     VALUES (?, ?, ?, NULL)`,
    // tse_client_id bleibt NULL bis Phase 2 (Fiskaly-Integration)
    [tenantId, name, tokenHash]
  );

  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId,
    userId:     req.auth!.userId,
    action:     'device.registered',
    entityType: 'device',
    entityId:   newId,
    diff:       { new: { name } },
    ipAddress:  req.ip,
    deviceId:   req.auth!.deviceId,
  });

  res.status(201).json({
    id:           newId,
    name,
    device_token: rawToken,   // ⚠️ Einmalig! Danach nicht mehr abrufbar.
    tse_client_id: null,      // wird in Phase 2 befüllt
  });
}

export async function revokeDevice(req: Request, res: Response): Promise<void> {
  // Nur owner darf Geräte sperren
  if (req.auth!.role !== 'owner') {
    res.status(403).json({ error: 'Nur Owner dürfen Geräte sperren.' });
    return;
  }

  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);

  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Geräte-ID.' });
    return;
  }

  // Eigenes aktives Gerät kann nicht gesperrt werden
  if (targetId === req.auth!.deviceId) {
    res.status(409).json({ error: 'Das aktuell verwendete Gerät kann nicht gesperrt werden.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, is_revoked FROM devices WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Gerät nicht gefunden.' });
    return;
  }

  if (rows[0].is_revoked) {
    res.status(409).json({ error: 'Gerät ist bereits gesperrt.' });
    return;
  }

  await db.execute(
    'UPDATE devices SET is_revoked = TRUE WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  await writeAuditLog({
    tenantId,
    userId:     req.auth!.userId,
    action:     'device.revoked',
    entityType: 'device',
    entityId:   targetId,
    diff:       { old: { name: rows[0].name, is_revoked: false }, new: { is_revoked: true } },
    ipAddress:  req.ip,
    deviceId:   req.auth!.deviceId,
  });

  res.json({ ok: true });
}

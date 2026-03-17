import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const createUserSchema = z.object({
  name:     z.string().min(1).max(255),
  email:    z.string().email(),
  password: z.string().min(8),
  role:     z.enum(['owner', 'manager', 'staff']),
  pin:      z.string().length(4).regex(/^\d{4}$/).nullable().optional(),
});

export const updateUserSchema = z.object({
  name: z.string().min(1).max(255).optional(),
  role: z.enum(['owner', 'manager', 'staff']).optional(),
  pin:  z.string().length(4).regex(/^\d{4}$/).nullable().optional(),
}).refine(data => Object.keys(data).length > 0, {
  message: 'Mindestens ein Feld muss angegeben werden.',
});

// ─── Role-Guard-Helper ───────────────────────────────────────────────────────

function requireRole(req: Request, res: Response, allowed: ('owner' | 'manager' | 'staff')[]): boolean {
  if (!req.auth || !allowed.includes(req.auth.role)) {
    res.status(403).json({ error: 'Keine Berechtigung für diese Aktion.' });
    return false;
  }
  return true;
}

// ─── Handler ────────────────────────────────────────────────────────────────

export async function listUsers(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const [rows] = await db.execute<any[]>(
    `SELECT id, name, email, role, is_active, created_at,
            (pin_hash IS NOT NULL) AS has_pin
     FROM users
     WHERE tenant_id = ? AND is_active = TRUE
     ORDER BY name ASC`,
    [tenantId]
  );

  res.json(rows);
}

export async function createUser(req: Request, res: Response): Promise<void> {
  if (!requireRole(req, res, ['owner', 'manager'])) return;

  const tenantId = req.auth!.tenantId;
  const { name, email, password, role, pin } = req.body as z.infer<typeof createUserSchema>;

  // manager darf keine owner anlegen
  if (req.auth!.role === 'manager' && role === 'owner') {
    res.status(403).json({ error: 'Manager dürfen keine Owner anlegen.' });
    return;
  }

  // E-Mail-Duplikat prüfen (pro Tenant)
  const [existing] = await db.execute<any[]>(
    'SELECT id FROM users WHERE email = ? AND tenant_id = ?',
    [email, tenantId]
  );
  if (existing.length > 0) {
    res.status(409).json({ error: 'E-Mail bereits vergeben.' });
    return;
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const pinHash      = pin ? await bcrypt.hash(pin, 12) : null;

  const [result] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [tenantId, name, email, passwordHash, role, pinHash]
  );

  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId,
    userId:     req.auth!.userId,
    action:     'user.created',
    entityType: 'user',
    entityId:   newId,
    diff:       { new: { name, email, role } },
    ipAddress:  req.ip,
    deviceId:   req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, name, email, role });
}

export async function updateUser(req: Request, res: Response): Promise<void> {
  if (!requireRole(req, res, ['owner', 'manager'])) return;

  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);

  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige User-ID.' });
    return;
  }

  // Ziel-User laden und Tenant-Zugehörigkeit prüfen
  const [rows] = await db.execute<any[]>(
    'SELECT id, name, email, role, is_active FROM users WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Benutzer nicht gefunden.' });
    return;
  }

  const target = rows[0];

  // manager darf keine owner bearbeiten
  if (req.auth!.role === 'manager' && target.role === 'owner') {
    res.status(403).json({ error: 'Manager dürfen Owner-Accounts nicht bearbeiten.' });
    return;
  }

  // manager darf keine owner-Rolle vergeben
  const { name, role, pin } = req.body as z.infer<typeof updateUserSchema>;
  if (req.auth!.role === 'manager' && role === 'owner') {
    res.status(403).json({ error: 'Manager dürfen keine Owner-Rolle vergeben.' });
    return;
  }

  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name !== undefined) { updates.push('name = ?');         values.push(name); }
  if (role !== undefined) { updates.push('role = ?');         values.push(role); }
  if (pin  !== undefined) {
    const hash = pin !== null ? await bcrypt.hash(pin, 12) : null;
    updates.push('pin_hash = ?');
    values.push(hash);
  }

  values.push(targetId, tenantId);

  await db.execute(
    `UPDATE users SET ${updates.join(', ')} WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId,
    userId:     req.auth!.userId,
    action:     'user.updated',
    entityType: 'user',
    entityId:   targetId,
    diff:       { old: { name: target.name, role: target.role }, new: { name, role } },
    ipAddress:  req.ip,
    deviceId:   req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function deleteUser(req: Request, res: Response): Promise<void> {
  if (!requireRole(req, res, ['owner', 'manager'])) return;

  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);

  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige User-ID.' });
    return;
  }

  // Eigenen Account kann man nicht löschen
  if (targetId === req.auth!.userId) {
    res.status(409).json({ error: 'Eigenen Account kann nicht deaktiviert werden.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, role FROM users WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Benutzer nicht gefunden.' });
    return;
  }

  const target = rows[0];

  // manager darf keine owner löschen
  if (req.auth!.role === 'manager' && target.role === 'owner') {
    res.status(403).json({ error: 'Manager dürfen Owner-Accounts nicht deaktivieren.' });
    return;
  }

  // Letzter Owner darf nicht gelöscht werden — FOR UPDATE verhindert Race Condition
  if (target.role === 'owner') {
    const conn = await (db as any).getConnection();
    try {
      await conn.beginTransaction();
      const [ownerCount] = await conn.execute(
        `SELECT COUNT(*) as cnt FROM users
         WHERE tenant_id = ? AND role = 'owner' AND is_active = TRUE FOR UPDATE`,
        [tenantId]
      );
      if (ownerCount[0].cnt <= 1) {
        await conn.rollback();
        res.status(409).json({ error: 'Der letzte Owner-Account kann nicht deaktiviert werden.' });
        return;
      }
      await conn.execute(
        'UPDATE users SET is_active = FALSE WHERE id = ? AND tenant_id = ?',
        [targetId, tenantId]
      );
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } else {
    // Soft delete — GoBD: kein DELETE auf users (User kann Autor von Finanzdaten sein)
    await db.execute(
      'UPDATE users SET is_active = FALSE WHERE id = ? AND tenant_id = ?',
      [targetId, tenantId]
    );
  }

  await writeAuditLog({
    tenantId,
    userId:     req.auth!.userId,
    action:     'user.deleted',
    entityType: 'user',
    entityId:   targetId,
    diff:       { old: { name: target.name, role: target.role } },
    ipAddress:  req.ip,
    deviceId:   req.auth!.deviceId,
  });

  res.json({ ok: true });
}

import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { db } from '../db/index.js';
import { AuthPayload } from '../middleware/authMiddleware.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const loginSchema = z.object({
  email:        z.string().email(),
  password:     z.string().min(1),
  device_token: z.string().min(1),  // Gerät identifiziert sich beim Login
});

export const refreshSchema = z.object({
  refresh_token: z.string().min(1),
});

export const pinSchema = z.object({
  device_token: z.string().min(1),
  pin:          z.string().length(4).regex(/^\d{4}$/),
});

// ─── Helpers ────────────────────────────────────────────────────────────────

function signTokens(payload: AuthPayload): { token: string; refreshToken: string } {
  const secret = process.env['JWT_SECRET'];
  if (!secret) throw new Error('JWT_SECRET nicht konfiguriert.');

  const token = jwt.sign(payload, secret, {
    expiresIn: (process.env['JWT_EXPIRY'] ?? '15m') as any,
  });

  const refreshToken = jwt.sign(
    { ...payload, type: 'refresh' },
    secret,
    { expiresIn: (process.env['JWT_REFRESH_EXPIRY'] ?? '7d') as any }
  );

  return { token, refreshToken };
}

async function findDeviceByToken(rawToken: string): Promise<any | null> {
  // Device-Token als SHA2-Hash in DB gespeichert — mysql2 direkt nutzen
  const [rows] = await db.execute<any[]>(
    `SELECT id, tenant_id, name, tse_client_id, is_revoked
     FROM devices
     WHERE device_token_hash = SHA2(?, 256)
       AND is_revoked = FALSE
     LIMIT 1`,
    [rawToken]
  );
  return rows[0] ?? null;
}

// ─── Handler ────────────────────────────────────────────────────────────────

export async function login(req: Request, res: Response): Promise<void> {
  const { email, password, device_token } = req.body as z.infer<typeof loginSchema>;

  // Gerät prüfen zuerst (verhindert User-Enumeration wenn Gerät unbekannt)
  const device = await findDeviceByToken(device_token);
  if (!device) {
    res.status(401).json({ error: 'Gerät nicht registriert oder gesperrt.' });
    return;
  }

  // User laden — tenant_id aus Gerät, nicht aus Request
  const [userRows] = await db.execute<any[]>(
    `SELECT id, name, email, password_hash, role, is_active
     FROM users
     WHERE email = ? AND tenant_id = ?
     LIMIT 1`,
    [email, device.tenant_id]
  );

  const user = userRows[0];

  if (!user || !user.is_active) {
    res.status(401).json({ error: 'E-Mail oder Passwort falsch.' });
    return;
  }

  const passwordMatch = await bcrypt.compare(password, user.password_hash);
  if (!passwordMatch) {
    res.status(401).json({ error: 'E-Mail oder Passwort falsch.' });
    return;
  }

  // last_seen_at aktualisieren (fire-and-forget)
  db.execute('UPDATE devices SET last_seen_at = NOW() WHERE id = ?', [device.id]).catch(() => {});

  const payload: AuthPayload = {
    userId:   user.id,
    tenantId: device.tenant_id,
    deviceId: device.id,
    role:     user.role,
  };

  const { token, refreshToken } = signTokens(payload);

  res.json({
    token,
    refreshToken,
    user: {
      id:   user.id,
      name: user.name,
      role: user.role,
    },
    device: {
      id:           device.id,
      name:         device.name,
      tse_client_id: device.tse_client_id,
    },
  });
}

export async function refresh(req: Request, res: Response): Promise<void> {
  const { refresh_token } = req.body as z.infer<typeof refreshSchema>;

  const secret = process.env['JWT_SECRET'];
  if (!secret) {
    res.status(500).json({ error: 'Server-Konfigurationsfehler.' });
    return;
  }

  let payload: AuthPayload & { type?: string };
  try {
    payload = jwt.verify(refresh_token, secret) as any;
  } catch {
    res.status(401).json({ error: 'Refresh-Token ungültig oder abgelaufen.' });
    return;
  }

  if (payload.type !== 'refresh') {
    res.status(401).json({ error: 'Kein Refresh-Token.' });
    return;
  }

  // Prüfen ob Gerät noch aktiv ist
  const [deviceRows] = await db.execute<any[]>(
    'SELECT id FROM devices WHERE id = ? AND tenant_id = ? AND is_revoked = FALSE',
    [payload.deviceId, payload.tenantId]
  );

  if (deviceRows.length === 0) {
    res.status(401).json({ error: 'Gerät gesperrt oder nicht gefunden.' });
    return;
  }

  // Prüfen ob User noch aktiv ist
  const [userRows] = await db.execute<any[]>(
    'SELECT id, role FROM users WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [payload.userId, payload.tenantId]
  );

  if (userRows.length === 0) {
    res.status(401).json({ error: 'Benutzer nicht aktiv.' });
    return;
  }

  const newPayload: AuthPayload = {
    userId:   payload.userId,
    tenantId: payload.tenantId,
    deviceId: payload.deviceId,
    role:     userRows[0].role,
  };

  const { token, refreshToken } = signTokens(newPayload);
  res.json({ token, refreshToken });
}

export async function logout(req: Request, res: Response): Promise<void> {
  // JWT ist stateless — Client löscht Token lokal.
  // Bei Geräteverlust: POST /devices/:id/revoke verwenden.
  res.json({ ok: true });
}

export async function pinSwitch(req: Request, res: Response): Promise<void> {
  const { device_token, pin } = req.body as z.infer<typeof pinSchema>;

  const device = await findDeviceByToken(device_token);
  if (!device) {
    res.status(401).json({ error: 'Gerät nicht registriert oder gesperrt.' });
    return;
  }

  // Alle aktiven User dieses Tenants mit PIN laden und vergleichen
  const [userRows] = await db.execute<any[]>(
    `SELECT id, name, role, pin_hash
     FROM users
     WHERE tenant_id = ? AND is_active = TRUE AND pin_hash IS NOT NULL`,
    [device.tenant_id]
  );

  let matchedUser: any = null;
  for (const user of userRows) {
    const match = await bcrypt.compare(pin, user.pin_hash);
    if (match) {
      matchedUser = user;
      break;
    }
  }

  if (!matchedUser) {
    res.status(401).json({ error: 'PIN falsch.' });
    return;
  }

  const payload: AuthPayload = {
    userId:   matchedUser.id,
    tenantId: device.tenant_id,
    deviceId: device.id,
    role:     matchedUser.role,
  };

  const { token, refreshToken } = signTokens(payload);

  res.json({
    token,
    refreshToken,
    user: {
      id:   matchedUser.id,
      name: matchedUser.name,
      role: matchedUser.role,
    },
  });
}

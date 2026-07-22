import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { db } from '../db/index.js';
import { AuthPayload } from '../middleware/authMiddleware.js';
import { logger } from '../logger.js';
import { captureException } from '../sentry.js';
import { writeAuditLog } from '../services/audit.js';
import { sendPasswordReset } from '../services/email/index.js';
import {
  consumePasswordResetToken,
  issuePasswordResetToken,
  passwordResetUrl,
} from '../services/passwordReset.js';
import {
  MIN_PASSWORD_LENGTH,
  renderResetErrorPage,
  renderResetFormPage,
  renderResetSuccessPage,
} from '../views/passwordResetPage.js';

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

// Wie beim Login liefert das Gerät den Tenant — `email` allein ist nicht
// eindeutig (UNIQUE ist (tenant_id, email)). Der Reset wird ohnehin am iPad
// angestoßen, das den Device-Token im Keychain hat.
export const forgotPasswordSchema = z.object({
  email:        z.string().email(),
  device_token: z.string().min(1),
});

// Die Reset-Seite ist HTML, kein JSON — deshalb hier `safeParse` im Controller
// statt `validationMiddleware` (dessen 422-JSON würde der Wirt im Browser roh
// sehen). Gleiches Muster wie bei den Query-Param-Routen, CLAUDE.md §Validierung.
export const resetPasswordQuerySchema = z.object({
  token: z.string().min(1).max(200),
});

export const resetPasswordFormSchema = z.object({
  token:               z.string().min(1).max(200),
  new_password:        z.string().min(MIN_PASSWORD_LENGTH).max(200),
  new_password_repeat: z.string().max(200).optional(),
});

// ─── Helpers ────────────────────────────────────────────────────────────────

const DEFAULT_SESSION_MAX_HOURS = 16;

// Absolutes Session-Limit in Sekunden — Refresh-Rotation verlängert die Session
// nicht über diesen Zeitraum hinaus (Schicht-Modell: 1x Login pro Tag).
function sessionMaxSeconds(): number {
  const hours = Number(process.env['SESSION_MAX_HOURS'] ?? DEFAULT_SESSION_MAX_HOURS);
  return (Number.isFinite(hours) && hours >= 0 ? hours : DEFAULT_SESSION_MAX_HOURS) * 3600;
}

function parseDurationSeconds(value: string, fallback: number): number {
  const match = /^(\d+)\s*(s|m|h|d)?$/.exec(value.trim());
  if (!match) return fallback;
  const units: Record<string, number> = { s: 1, m: 60, h: 3600, d: 86400 };
  return Number(match[1]) * units[match[2] ?? 's']!;
}

function signTokens(
  payload: AuthPayload,
  sessionStart?: number
): { token: string; refreshToken: string } {
  const secret = process.env['JWT_SECRET'];
  if (!secret) throw new Error('JWT_SECRET nicht konfiguriert.');

  const now = Math.floor(Date.now() / 1000);
  const start = sessionStart ?? now;

  const token = jwt.sign(payload, secret, {
    expiresIn: (process.env['JWT_EXPIRY'] ?? '15m') as any,
  });

  // Refresh-Token läuft spätestens mit dem absoluten Session-Limit ab —
  // damit ist es nach Ablauf auch kryptografisch tot, nicht nur per Handler-Check.
  const baseRefreshSeconds = parseDurationSeconds(
    process.env['JWT_REFRESH_EXPIRY'] ?? '7d',
    7 * 86400
  );
  const remainingSeconds = start + sessionMaxSeconds() - now;
  const refreshExpiresIn = Math.max(1, Math.min(baseRefreshSeconds, remainingSeconds));

  const refreshToken = jwt.sign(
    { ...payload, type: 'refresh', session_start: start },
    secret,
    { expiresIn: refreshExpiresIn }
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

  let payload: AuthPayload & { type?: string; session_start?: number };
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

  // Absolutes Session-Limit: Rotation verlängert die Session nicht.
  // Alt-Tokens ohne session_start (vor Einführung des Limits) → Re-Login.
  const sessionStart = payload.session_start;
  if (
    typeof sessionStart !== 'number' ||
    Math.floor(Date.now() / 1000) - sessionStart > sessionMaxSeconds()
  ) {
    res.status(401).json({ error: 'Sitzung abgelaufen — bitte neu anmelden.' });
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
    `SELECT id, role, UNIX_TIMESTAMP(password_changed_at) AS password_changed_ts
       FROM users
      WHERE id = ? AND tenant_id = ? AND is_active = TRUE`,
    [payload.userId, payload.tenantId]
  );

  if (userRows.length === 0) {
    res.status(401).json({ error: 'Benutzer nicht aktiv.' });
    return;
  }

  // Passwortwechsel beendet ältere Sitzungen (S08): Wer das Passwort zurücksetzt,
  // weil es kompromittiert wurde, sperrt damit auch das gestohlene Refresh-Token
  // aus — sonst überlebte es den Reset bis zu SESSION_MAX_HOURS.
  // Der Vergleich läuft über UNIX_TIMESTAMP, damit die Zeitzone der DB egal ist.
  const passwordChangedTs = userRows[0].password_changed_ts;
  if (passwordChangedTs !== null && sessionStart < Number(passwordChangedTs)) {
    res.status(401).json({ error: 'Sitzung abgelaufen — bitte neu anmelden.' });
    return;
  }

  const newPayload: AuthPayload = {
    userId:   payload.userId,
    tenantId: payload.tenantId,
    deviceId: payload.deviceId,
    role:     userRows[0].role,
  };

  const { token, refreshToken } = signTokens(newPayload, sessionStart);
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

// ─── Passwort-Reset (S08 / OFFEN.md B3) ─────────────────────────────────────

/**
 * Antwortet **immer** 200 — unbekannte E-Mail, gesperrtes Gerät, inaktiver
 * Nutzer und gedrosselte Anfrage sind von außen nicht unterscheidbar. Sonst
 * wäre dieser Endpoint ein Verzeichnis aller Konten eines Betriebs.
 */
export async function forgotPassword(req: Request, res: Response): Promise<void> {
  const { email, device_token } = req.body as z.infer<typeof forgotPasswordSchema>;

  // Antwort zuerst festlegen, damit unten kein Pfad versehentlich mehr verrät.
  const ok = { ok: true as const };

  const device = await findDeviceByToken(device_token);
  if (!device) {
    res.json(ok);
    return;
  }

  const [rows] = await db.execute<any[]>(
    `SELECT u.id, u.email, t.name AS tenant_name
       FROM users u
       JOIN tenants t ON t.id = u.tenant_id
      WHERE u.email = ? AND u.tenant_id = ? AND u.is_active = TRUE
      LIMIT 1`,
    [email, device.tenant_id]
  );
  const user = rows[0];
  if (!user) {
    logger.info({ tenant: device.tenant_id }, 'Passwort-Reset für unbekannte Adresse angefragt');
    res.json(ok);
    return;
  }

  const issued = await issuePasswordResetToken({
    tenantId: device.tenant_id,
    userId:   user.id,
  });
  if (!issued) {
    logger.warn(
      { tenant: device.tenant_id, userId: user.id },
      'Passwort-Reset gedrosselt (Stundenlimit erreicht)'
    );
    res.json(ok);
    return;
  }

  await sendPasswordReset({
    tenantId:   device.tenant_id,
    tenantName: user.tenant_name,
    recipient:  user.email,
    // Idempotenz-Marker: die Token-Zeilen-ID = pro ausgestelltem Token genau
    // eine Mail. Bewusst nicht der Token selbst (Klartext gehört nicht in
    // email_queue) und bewusst kein Zeitstempel (zwei Anfragen in derselben
    // Sekunde würden sich sonst die Mail wegnehmen).
    requestId:  `${user.id}:${issued.id}`,
    resetUrl:   passwordResetUrl(issued.rawToken),
    expiresAt:  issued.expiresAt,
  });

  await writeAuditLog({
    tenantId:   device.tenant_id,
    userId:     user.id,
    action:     'user.password_reset_requested',
    entityType: 'user',
    entityId:   user.id,
    ipAddress:  req.ip,
    deviceId:   device.id,
  }).catch((err: unknown) => {
    logger.error({ err }, 'audit_log für Passwort-Reset-Anfrage fehlgeschlagen');
  });

  res.json(ok);
}

/** GET /auth/reset-password?token=… — die Seite aus der Mail. */
export function showResetPasswordPage(req: Request, res: Response): void {
  noStore(res);
  const parsed = resetPasswordQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).type('html').send(renderResetErrorPage('invalid'));
    return;
  }
  // Der Token wird hier bewusst NICHT gegen die DB geprüft: Ein gültiger Token
  // soll nicht schon durch das Öffnen der Seite verbraucht wirken, und ein
  // Fehlschlag zeigt sich beim Absenden ohnehin. Das Formular ist harmlos.
  res.type('html').send(renderResetFormPage({ token: parsed.data.token }));
}

/** POST /auth/reset-password — Formular-Submit der Seite oben (urlencoded). */
export async function resetPassword(req: Request, res: Response): Promise<void> {
  noStore(res);
  const parsed = resetPasswordFormSchema.safeParse(req.body);

  if (!parsed.success) {
    const token = typeof (req.body as any)?.token === 'string' ? (req.body as any).token : '';
    if (!token) {
      res.status(400).type('html').send(renderResetErrorPage('invalid'));
      return;
    }
    res.status(422).type('html').send(
      renderResetFormPage({
        token,
        error: `Das Passwort braucht mindestens ${MIN_PASSWORD_LENGTH} Zeichen.`,
      })
    );
    return;
  }

  const { token, new_password, new_password_repeat } = parsed.data;

  // Ohne JavaScript kann nur der Server vergleichen.
  if (new_password_repeat !== undefined && new_password_repeat !== new_password) {
    res.status(422).type('html').send(
      renderResetFormPage({ token, error: 'Die beiden Passwörter stimmen nicht überein.' })
    );
    return;
  }

  const result = await consumePasswordResetToken(token, new_password);

  if (!result.ok) {
    res.status(400).type('html').send(renderResetErrorPage(result.reason));
    return;
  }

  await writeAuditLog({
    tenantId:   result.tenantId,
    userId:     result.userId,
    action:     'user.password_reset',
    entityType: 'user',
    entityId:   result.userId,
    ipAddress:  req.ip,
  }).catch((err: unknown) => {
    // Passwort ist bereits geändert — der fehlende Nachweis ist ein
    // Betriebsvorfall, aber kein Grund, den Nutzer scheitern zu lassen.
    logger.error({ err }, 'audit_log für Passwort-Reset fehlgeschlagen');
    captureException(err instanceof Error ? err : new Error(String(err)), {
      tenant: result.tenantId,
      source: 'auth:password-reset-audit',
    });
  });

  res.type('html').send(renderResetSuccessPage());
}

/** Reset-Seiten tragen einen Token in der URL — sie dürfen weder im
 *  Browser-Cache noch in einem Proxy liegen bleiben. */
function noStore(res: Response): void {
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  res.setHeader('Referrer-Policy', 'no-referrer');
}

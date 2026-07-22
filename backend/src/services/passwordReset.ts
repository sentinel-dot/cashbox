// services/passwordReset.ts — S08 (OFFEN.md B3): der EINE Passwort-Reset-Pfad.
//
// Aufgeteilt in pure Funktionen (Token erzeugen/hashen, URL bauen, Ablauf
// bewerten — unit-testbar ohne DB) und zwei DB-Operationen: Token ausstellen
// und Token einlösen. Der Controller entscheidet nur noch über die Antwort.
//
// Leitplanken:
//   - Klartext-Token existiert genau einmal (in der Mail), in der DB nur SHA-256.
//   - Einmal gültig: Einlösen setzt used_at; ein neuer Token entwertet ältere.
//   - Kein User-Enumeration-Leak: der Controller antwortet immer 200, dieser
//     Service sagt nie „User existiert nicht" nach außen.
import crypto from 'crypto';
import bcrypt from 'bcrypt';
import type { PoolConnection } from 'mysql2/promise';
import { db } from '../db/index.js';

/** Gültigkeitsdauer des Links. Der Text im Mail-Template nennt „1 Stunde" —
 *  beides zusammen ändern. */
export const RESET_TTL_MINUTES = 60;

/** Mehr Reset-Mails pro Stunde und Nutzer verschickt der Server nicht. Schützt
 *  das Postfach eines fremden Nutzers vor Mail-Bombing über ein Formular, das
 *  bewusst immer 200 antwortet. */
export const MAX_REQUESTS_PER_HOUR = 3;

/** bcrypt-Kosten wie überall sonst im Projekt (authController, Seed, Onboarding). */
const BCRYPT_ROUNDS = 10;

/** 32 Byte Zufall, base64url — URL-sicher ohne Encoding und nicht erratbar. */
export function generateResetToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

/** Klartext-Token → Hex-Hash für die DB. Bewusst schnell und indexierbar
 *  (Begründung in Migration V013). */
export function hashResetToken(raw: string): string {
  return crypto.createHash('sha256').update(raw).digest('hex');
}

/**
 * Ziel des Links in der Mail. Zeigt auf das Backend, nicht auf die App: Die
 * Reset-Seite wird serverseitig gerendert (S08-Entscheidung), damit der Wirt
 * sie von jedem Gerät öffnen kann — auch wenn das iPad gerade an der Theke steht.
 */
export function passwordResetUrl(rawToken: string): string {
  const base = (
    process.env['PUBLIC_API_URL'] ??
    process.env['APP_URL'] ??
    'https://api.cashbox.de'
  ).replace(/\/$/, '');
  return `${base}/auth/reset-password?token=${encodeURIComponent(rawToken)}`;
}

export interface IssuedToken {
  /** ID der Token-Zeile. Dient dem Aufrufer als Idempotenz-Marker für die Mail:
   *  pro ausgestelltem Token genau eine Mail, auch bei zwei Anfragen in
   *  derselben Sekunde (ein Zeitstempel wäre dafür zu grob — die zweite Mail
   *  fiele weg, während der erste Link bereits entwertet ist). */
  id: number;
  rawToken: string;
  expiresAt: Date;
}

/**
 * Stellt einen frischen Token für einen bekannten, aktiven Nutzer aus und
 * entwertet dabei alle älteren offenen Tokens desselben Nutzers (es soll immer
 * höchstens ein Link gültig sein — sonst bleibt nach „Link vergessen, nochmal
 * anfordern" der alte Link stundenlang scharf).
 *
 * Gibt `null` zurück, wenn das Stundenlimit erreicht ist. Der Aufrufer antwortet
 * trotzdem 200 — von außen ist „gedrosselt" nicht von „Mail unterwegs"
 * unterscheidbar.
 */
export async function issuePasswordResetToken(input: {
  tenantId: number;
  userId: number;
}): Promise<IssuedToken | null> {
  const [recent] = await db.execute<any[]>(
    `SELECT COUNT(*) AS cnt
       FROM password_reset_tokens
      WHERE tenant_id = ? AND user_id = ?
        AND created_at > NOW() - INTERVAL 1 HOUR`,
    [input.tenantId, input.userId]
  );
  if (Number(recent[0]?.cnt ?? 0) >= MAX_REQUESTS_PER_HOUR) return null;

  // Ältere offene Tokens entwerten (used_at ist ein operatives Zustandsfeld,
  // password_reset_tokens ist keine Finanztabelle — UPDATE erlaubt).
  await db.execute(
    `UPDATE password_reset_tokens
        SET used_at = NOW()
      WHERE tenant_id = ? AND user_id = ? AND used_at IS NULL`,
    [input.tenantId, input.userId]
  );

  const rawToken = generateResetToken();
  const [inserted] = await db.execute<any>(
    `INSERT INTO password_reset_tokens (tenant_id, user_id, token_hash, expires_at)
     VALUES (?, ?, ?, NOW() + INTERVAL ? MINUTE)`,
    [input.tenantId, input.userId, hashResetToken(rawToken), RESET_TTL_MINUTES]
  );

  // Ablaufzeitpunkt aus der DB lesen, nicht in Node ausrechnen: In der Mail
  // steht dieselbe Uhrzeit, gegen die der Server später prüft.
  const [rows] = await db.execute<any[]>(
    'SELECT expires_at FROM password_reset_tokens WHERE id = ?',
    [inserted.insertId]
  );

  return {
    id: inserted.insertId,
    rawToken,
    expiresAt: new Date(rows[0].expires_at),
  };
}

/** Warum ein Token nicht (mehr) eingelöst werden kann. Die Reset-Seite macht
 *  daraus einen verständlichen Satz — bewusst unterscheidbar, weil der Nutzer
 *  hier den Token schon in der Hand hat: Es gibt nichts mehr zu enumerieren. */
export type ConsumeFailure = 'invalid' | 'expired' | 'used' | 'user_inactive';

export type ConsumeResult =
  | { ok: true; tenantId: number; userId: number }
  | { ok: false; reason: ConsumeFailure };

/**
 * Löst den Token ein und setzt das neue Passwort — in einer Transaktion, unter
 * `FOR UPDATE` auf der Token-Zeile: Zwei parallele Submits desselben Links
 * dürfen nicht beide „erfolgreich" melden.
 *
 * `users.password_changed_at` wird mitgesetzt; darüber entwertet `/auth/refresh`
 * alle Sitzungen, die vor dem Reset begonnen haben.
 */
export async function consumePasswordResetToken(
  rawToken: string,
  newPassword: string
): Promise<ConsumeResult> {
  const conn = (await (db as any).getConnection()) as PoolConnection;
  try {
    await conn.beginTransaction();

    const [rows] = await conn.execute<any[]>(
      `SELECT id, tenant_id, user_id, used_at,
              (expires_at < NOW()) AS is_expired
         FROM password_reset_tokens
        WHERE token_hash = ?
        FOR UPDATE`,
      [hashResetToken(rawToken)]
    );

    const row = rows[0];
    if (!row) {
      await conn.rollback();
      return { ok: false, reason: 'invalid' };
    }
    if (row.used_at) {
      await conn.rollback();
      return { ok: false, reason: 'used' };
    }
    if (Number(row.is_expired) === 1) {
      await conn.rollback();
      return { ok: false, reason: 'expired' };
    }

    // Deaktivierte/gelöschte Nutzer bekommen kein neues Passwort — ein
    // Soft-Delete darf nicht per alter Reset-Mail rückgängig gemacht werden.
    const [userRows] = await conn.execute<any[]>(
      'SELECT id FROM users WHERE id = ? AND tenant_id = ? AND is_active = TRUE FOR UPDATE',
      [row.user_id, row.tenant_id]
    );
    if (userRows.length === 0) {
      await conn.rollback();
      return { ok: false, reason: 'user_inactive' };
    }

    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);

    await conn.execute(
      'UPDATE users SET password_hash = ?, password_changed_at = NOW() WHERE id = ? AND tenant_id = ?',
      [passwordHash, row.user_id, row.tenant_id]
    );
    await conn.execute(
      'UPDATE password_reset_tokens SET used_at = NOW() WHERE id = ?',
      [row.id]
    );

    await conn.commit();
    return { ok: true, tenantId: row.tenant_id, userId: row.user_id };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

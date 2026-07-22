// Gemeinsames Vokabular aller Cron-Jobs (S07).
//
// Jeder Job ist eine gewöhnliche async-Funktion ohne Express, ohne Scheduler und
// ohne globalen Zustand: `run()` → Zahlen. Damit lässt sich jeder Job im
// Integrationstest einzeln auslösen (DoD S07) und per `npm run job -- <name>`
// auch von Hand auf dem Server.
//
// Idempotenz ist Pflicht, nicht Kür: Ein doppelter Lauf (Deploy, Neustart,
// zweiter Prozess) darf keine zweite Mail schicken und keinen zweiten Z-Bericht
// schreiben. Jeder Job hat dafür einen expliziten Marker in der DB —
// email_queue.idempotency_key, tse_outages.notified_at, offline_queue.alerted_at
// oder die Existenz der z_reports-Zeile.
import { db } from '../db/index.js';

export type JobResult = Record<string, number>;

export type JobDefinition = {
  /** Stabiler Name — CLI-Argument, Log-Feld und Testreferenz. */
  name: string;
  /** node-cron-Ausdruck, ausgewertet in Europe/Berlin (siehe cron.ts). */
  schedule: string;
  description: string;
  run: () => Promise<JobResult>;
};

export type OwnerRecipient = {
  userId: number;
  email: string;
  tenantName: string;
};

/**
 * Empfänger für Betriebsmails eines Tenants: der dienstälteste aktive Owner.
 *
 * Bewusst genau einer und nicht "alle Owner": Die Idempotenz-Schlüssel der
 * Mail-Queue sind tenant-gescopt (`trial_warning:42:day10`) — mehrere Empfänger
 * bräuchten mehrere Schlüssel. Solange ein Betrieb einen Inhaber hat, ist das
 * die ehrlichere Zustellung. Kein aktiver Owner → null (der Job zählt das mit,
 * statt still nichts zu tun).
 */
export async function ownerRecipient(tenantId: number): Promise<OwnerRecipient | null> {
  const [rows] = await db.execute<any[]>(
    `SELECT u.id, u.email, t.name AS tenant_name
       FROM users u
       JOIN tenants t ON t.id = u.tenant_id
      WHERE u.tenant_id = ? AND u.role = 'owner' AND u.is_active = 1
      ORDER BY u.id ASC
      LIMIT 1`,
    [tenantId]
  );
  const row = rows[0];
  if (!row) return null;
  return { userId: row.id as number, email: row.email as string, tenantName: row.tenant_name as string };
}

// Stündlich: Kassensitzungen, die länger als 24 h offen sind.
//
// GoBD verlangt den täglichen Kassenabschluss. Eine Sitzung, die über Nacht
// offen bleibt, ist fast immer ein vergessenes „Schicht beenden" — und je später
// sie geschlossen wird, desto weniger sagt der gezählte Kassenbestand aus.
// Stündlich statt täglich, weil die Mail pro Sitzung genau einmal rausgeht
// (Idempotenz-Schlüssel `long_open_session:<tenant>:<session>:24h`) und ein
// Hinweis am selben Abend noch etwas retten kann.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { sendLongOpenSessionWarning } from '../services/email/index.js';
import { ownerRecipient, type JobResult } from './shared.js';

const OPEN_SESSION_THRESHOLD_HOURS = 24;

export async function runLongOpenSessions(): Promise<JobResult> {
  const [rows] = await db.execute<any[]>(
    `SELECT s.id, s.tenant_id, s.opened_at, d.name AS device_name
       FROM cash_register_sessions s
       JOIN devices d ON d.id = s.device_id AND d.tenant_id = s.tenant_id
      WHERE s.status = 'open'
        AND s.opened_at < NOW() - INTERVAL ? HOUR`,
    [OPEN_SESSION_THRESHOLD_HOURS]
  );

  const result = { found: rows.length, queued: 0, skipped: 0, no_recipient: 0 };
  const observedAt = new Date();

  for (const session of rows) {
    const owner = await ownerRecipient(session.tenant_id);
    if (!owner) {
      result.no_recipient++;
      logger.warn({ tenant: session.tenant_id, session: session.id }, 'Lang offene Sitzung ohne Empfänger');
      continue;
    }

    const queued = await sendLongOpenSessionWarning({
      tenantId:   session.tenant_id,
      tenantName: owner.tenantName,
      recipient:  owner.email,
      sessionId:  session.id,
      deviceName: session.device_name,
      openedAt:   new Date(session.opened_at),
      observedAt,
    });
    if (queued) {
      result.queued++;
      logger.warn(
        { tenant: session.tenant_id, session: session.id, opened_at: session.opened_at },
        'Kassensitzung länger als 24 h offen — Owner benachrichtigt'
      );
    } else {
      result.skipped++;
    }
  }

  return result;
}

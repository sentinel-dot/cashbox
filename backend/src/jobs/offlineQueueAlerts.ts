// Stündlich: endgültig gescheiterte Offline-Queue-Einträge melden.
//
// Ein 'failed'-Eintrag heißt: dieser Bon bekommt seine TSE-Signatur nicht mehr
// von allein. Das ist kein Retry-Fall mehr, sondern ein Vorfall, der einen
// Menschen braucht (Fiskaly-Konfiguration, verwaister Eintrag, 4xx). Gemeldet
// wird jeder Eintrag genau einmal — `alerted_at` (V012) ist der Marker.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { captureException } from '../sentry.js';
import type { JobResult } from './shared.js';

const ALERT_BATCH_SIZE = 50;

export async function runOfflineQueueAlerts(): Promise<JobResult> {
  const [rows] = await db.execute<any[]>(
    `SELECT id, tenant_id, device_id, order_id, retry_count, error_message
       FROM offline_queue
      WHERE status = 'failed' AND alerted_at IS NULL
      ORDER BY id ASC
      LIMIT ?`,
    [ALERT_BATCH_SIZE]
  );

  const result = { alerted: 0 };

  for (const entry of rows) {
    // Marker zuerst: ein zweiter Lauf (oder ein zweiter Prozess) soll denselben
    // Vorfall nicht erneut melden. Verlorene Meldung wäre schlimmer als eine
    // doppelte — deshalb bedingtes UPDATE und nur bei affectedRows = 1 melden.
    const [claim] = await db.execute<any>(
      `UPDATE offline_queue SET alerted_at = NOW() WHERE id = ? AND alerted_at IS NULL`,
      [entry.id]
    );
    if (claim.affectedRows !== 1) continue;

    result.alerted++;
    logger.error(
      {
        tenant: entry.tenant_id,
        device: entry.device_id,
        order: entry.order_id,
        queue_entry: entry.id,
        retry_count: entry.retry_count,
        queue_error: entry.error_message,
      },
      'Offline-Queue-Eintrag endgültig fehlgeschlagen — Bon bleibt ohne TSE-Signatur'
    );
    captureException(
      new Error(
        `Offline-Queue-Eintrag ${entry.id} endgültig fehlgeschlagen (Order ${entry.order_id}): ` +
          `${entry.error_message ?? 'ohne Fehlermeldung'}`
      ),
      { tenant: entry.tenant_id, source: 'cron:offline-queue-alerts' }
    );
  }

  return result;
}

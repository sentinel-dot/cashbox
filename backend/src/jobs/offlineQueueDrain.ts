// Stündlich: serverseitige Nachsignierung offener Offline-Bons.
//
// Bisher lief die Nachsignierung nur, wenn ein iPad POST /sync/offline-queue
// schickte. Ein Gerät, das nach dem Ausfall nicht mehr online geht (kaputt,
// verkauft, im Schrank), hinterlässt damit dauerhaft unsignierte Bons — und
// KassenSichV kennt keine Ausrede „das iPad kam nicht wieder". Der Drain läuft
// deshalb auch ohne Client, über exakt denselben Code (services/offlineSync.ts)
// und dieselben atomaren Claims, damit beide Wege nebeneinander laufen dürfen.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { syncOfflineQueueForTenant } from '../services/offlineSync.js';
import type { JobResult } from './shared.js';

export async function runOfflineQueueDrain(): Promise<JobResult> {
  // 'processing' mitnehmen: hängende Claims setzt syncOfflineQueueForTenant
  // selbst zurück — ein Tenant, dessen Einträge alle 'processing' sind, wäre
  // sonst für den Cron unsichtbar und würde nie mehr aufgeräumt.
  const [tenants] = await db.execute<any[]>(
    `SELECT DISTINCT tenant_id FROM offline_queue WHERE status IN ('pending', 'processing')`
  );

  const result = { tenants: tenants.length, processed: 0, succeeded: 0, failed: 0, requeued: 0 };

  for (const { tenant_id: tenantId } of tenants) {
    try {
      // userId = null: kein angemeldeter Benutzer, der Server signiert nach.
      const r = await syncOfflineQueueForTenant({ tenantId, userId: null });
      result.processed += r.processed;
      result.succeeded += r.succeeded;
      result.failed    += r.failed;
      result.requeued  += r.requeued;
    } catch (err) {
      // Ein kaputter Tenant darf die anderen nicht blockieren — der Job-Wrapper
      // meldet nur den Gesamtfehler, hier bleibt die Schleife am Leben.
      logger.error({ err, tenant: tenantId }, 'Offline-Queue-Drain für Tenant fehlgeschlagen');
    }
  }

  return result;
}

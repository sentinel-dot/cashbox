// Nachsignierung offline erstellter Bons — der eigentliche Motor hinter
// POST /sync/offline-queue UND dem stündlichen Cron-Drain aus S07.
//
// Warum als Service und nicht (mehr) im Controller: Die Nachsignierung ist eine
// KassenSichV-Pflicht und darf nicht davon abhängen, dass das iPad wiederkommt.
// Ein iPad, das im Schrank liegt oder verkauft wurde, hinterlässt sonst dauerhaft
// unsignierte Bons. Deshalb ruft derselbe Code jetzt auch der Server-Cron auf —
// mit userId = null (kein angemeldeter Benutzer).
import { db } from '../db/index.js';
import { processTseTransaction } from './fiskaly.js';
import { writeAuditLog } from './audit.js';

// Stuck-'processing'-Einträge nach 5 Min zurücksetzen (Crash-Recovery)
const STUCK_THRESHOLD_MINUTES = 5;
// Einträge ohne receipt_id erst nach dieser Frist endgültig failen —
// payOrder verknüpft die receipt_id erst nach Abschluss der DB-Transaktion
const NO_RECEIPT_FAIL_MINUTES = 10;
export const DEFAULT_BATCH_SIZE = 20;

export type OfflineSyncResult = {
  processed:  number;
  succeeded:  number;
  failed:     number;
  requeued:   number;
};

/**
 * Verarbeitet bis zu `batchSize` 'pending'-Einträge eines Tenants.
 *
 * Nebenläufig sicher: jeder Eintrag wird per bedingtem UPDATE geclaimt, ein
 * paralleler Lauf (iPad-Sync + Cron gleichzeitig) bekommt affectedRows = 0 und
 * überspringt. Das ist die Bedingung dafür, dass Cron und Client nebeneinander
 * laufen dürfen, ohne eine TSE-Transaktion doppelt zu senden.
 */
export async function syncOfflineQueueForTenant(params: {
  tenantId: number;
  /** Auslöser für das Audit-Log; null = serverseitiger Cron-Lauf. */
  userId: number | null;
  batchSize?: number;
}): Promise<OfflineSyncResult> {
  const { tenantId, userId } = params;
  const batchSize = params.batchSize ?? DEFAULT_BATCH_SIZE;

  // Stuck 'processing'-Einträge zurücksetzen (Crash-Recovery, UPDATE erlaubt).
  // Maßgeblich ist der Claim-Zeitpunkt (processing_started_at), nicht created_at —
  // sonst würde ein alter, gerade geclaimter Eintrag sofort wieder freigegeben.
  await db.execute(
    `UPDATE offline_queue
     SET status = 'pending', error_message = 'Reset nach processing-Timeout'
     WHERE tenant_id = ? AND status = 'processing'
       AND processing_started_at IS NOT NULL
       AND processing_started_at < NOW() - INTERVAL ? MINUTE`,
    [tenantId, STUCK_THRESHOLD_MINUTES]
  );

  // Pending-Einträge laden mit TSE-Konfiguration des Original-Geräts
  const [entries] = await db.execute<any[]>(
    `SELECT q.id, q.device_id, q.order_id, q.idempotency_key, q.payload_json,
            q.retry_count, q.created_at,
            d.tse_client_id,
            t.fiskaly_tss_id
     FROM offline_queue q
     JOIN devices d ON d.id = q.device_id AND d.tenant_id = q.tenant_id
     JOIN tenants t ON t.id = q.tenant_id
     WHERE q.tenant_id = ? AND q.status = 'pending'
     ORDER BY q.created_at ASC
     LIMIT ?`,
    [tenantId, batchSize]
  );

  const result: OfflineSyncResult = { processed: 0, succeeded: 0, failed: 0, requeued: 0 };

  for (const entry of entries) {
    // Atomarer Claim — paralleler Sync-Aufruf darf denselben Eintrag nicht doppelt verarbeiten
    const [claim] = await db.execute<any>(
      `UPDATE offline_queue
       SET status = 'processing', processing_started_at = NOW()
       WHERE id = ? AND tenant_id = ? AND status = 'pending'`,
      [entry.id, tenantId]
    );
    if (claim.affectedRows !== 1) continue; // bereits von anderem Aufruf geclaimt

    const payload = typeof entry.payload_json === 'string'
      ? JSON.parse(entry.payload_json)
      : entry.payload_json;

    result.processed++;

    // Kein receipt_id → Zahlung (noch) nicht abgeschlossen. payOrder trägt die
    // receipt_id erst nach Commit der Zahlungs-TX ein — frische Einträge daher
    // zurückstellen, erst nach Frist endgültig failen (TSE-TX wäre sonst waisig).
    if (!payload.receipt_id) {
      const ageMs = Date.now() - new Date(entry.created_at).getTime();
      if (ageMs >= NO_RECEIPT_FAIL_MINUTES * 60_000) {
        await db.execute(
          `UPDATE offline_queue
           SET status = 'failed', retry_count = retry_count + 1,
               error_message = 'Keine receipt_id — Zahlung nicht abgeschlossen'
           WHERE id = ? AND tenant_id = ?`,
          [entry.id, tenantId]
        );
        result.failed++;
      } else {
        await db.execute(
          `UPDATE offline_queue
           SET status = 'pending', error_message = 'Wartet auf receipt_id (Zahlung läuft noch)'
           WHERE id = ? AND tenant_id = ?`,
          [entry.id, tenantId]
        );
        result.requeued++;
      }
      continue;
    }

    try {
      const tseResult = await processTseTransaction({
        tenantId,
        deviceId:        entry.device_id,
        orderId:         entry.order_id,
        userId,
        tssId:           entry.fiskaly_tss_id  ?? '',
        clientId:        entry.tse_client_id   ?? '',
        vat7GrossCents:  payload.vat7GrossCents,
        vat19GrossCents: payload.vat19GrossCents,
        payments:        payload.payments,
        receiptType:     payload.receiptType ?? 'RECEIPT',
        idempotencyKey:  entry.idempotency_key,
      });

      if (!tseResult.pending) {
        // TSE-Metadaten auf dem Receipt nachtragen (kein Finanzdatum — erlaubtes UPDATE)
        await db.execute(
          `UPDATE receipts
           SET tse_pending           = 0,
               tse_transaction_id    = ?,
               tse_serial_number     = ?,
               tse_signature         = ?,
               tse_counter           = ?,
               tse_transaction_start = ?,
               tse_transaction_end   = ?
           WHERE id = ? AND tenant_id = ?`,
          [
            tseResult.tseTransactionId    ?? null,
            tseResult.tseSerialNumber     ?? null,
            tseResult.tseSignature        ?? null,
            tseResult.tseCounter          ?? null,
            tseResult.tseTransactionStart ?? null,
            tseResult.tseTransactionEnd   ?? null,
            payload.receipt_id,
            tenantId,
          ]
        );

        await db.execute(
          `UPDATE offline_queue
           SET status = 'completed', synced_at = NOW(), error_message = NULL
           WHERE id = ? AND tenant_id = ?`,
          [entry.id, tenantId]
        );

        result.succeeded++;

        writeAuditLog({
          tenantId, userId,
          action: 'tse.offline_synced',
          entityType: 'receipt', entityId: payload.receipt_id,
          diff: { new: { tse_transaction_id: tseResult.tseTransactionId, idempotency_key: entry.idempotency_key } },
          deviceId: entry.device_id,
        }).catch(() => {});

      } else {
        // TSE noch nicht erreichbar — transient: zurück auf 'pending', damit der
        // nächste Sync-Lauf erneut versucht (KassenSichV: Bons MÜSSEN nachsigniert werden)
        await db.execute(
          `UPDATE offline_queue
           SET status = 'pending', retry_count = retry_count + 1,
               error_message = 'TSE nicht erreichbar'
           WHERE id = ? AND tenant_id = ?`,
          [entry.id, tenantId]
        );
        result.requeued++;
      }

    } catch (err: any) {
      const message = (err.message ?? String(err)).slice(0, 500);
      // 4xx-Validierungsfehler sind endgültig → failed.
      // Alles andere (Netzwerk, 5xx, Timeout) ist transient → pending für Retry.
      const isPermanent = err.status && err.status >= 400 && err.status < 500
        && err.status !== 408 && err.status !== 429;
      await db.execute(
        `UPDATE offline_queue
         SET status = ?, retry_count = retry_count + 1, error_message = ?
         WHERE id = ? AND tenant_id = ?`,
        [isPermanent ? 'failed' : 'pending', message, entry.id, tenantId]
      );
      if (isPermanent) result.failed++; else result.requeued++;
    }
  }

  return result;
}

/** Zählt die verbleibenden 'pending'-Einträge eines Tenants. */
export async function countPendingEntries(tenantId: number): Promise<number> {
  const [rows] = await db.execute<any[]>(
    `SELECT COUNT(*) AS remaining FROM offline_queue WHERE tenant_id = ? AND status = 'pending'`,
    [tenantId]
  );
  return Number(rows[0].remaining);
}

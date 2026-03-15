import { Request, Response } from 'express';
import { db } from '../db/index.js';
import { processTseTransaction } from '../services/fiskaly.js';
import { writeAuditLog } from '../services/audit.js';

// Stuck-'processing'-Einträge nach 5 Min zurücksetzen (Crash-Recovery)
const STUCK_THRESHOLD_MINUTES = 5;
const BATCH_SIZE = 20;

// ─── GET /sync/offline-queue ──────────────────────────────────────────────────

export async function getOfflineQueueStatus(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const [rows] = await db.execute<any[]>(
    `SELECT status, COUNT(*) AS count
     FROM offline_queue
     WHERE tenant_id = ?
     GROUP BY status`,
    [tenantId]
  );

  const counts: Record<string, number> = {};
  for (const row of rows) { counts[row.status] = Number(row.count); }

  res.json({
    pending:    counts['pending']    ?? 0,
    processing: counts['processing'] ?? 0,
    completed:  counts['completed']  ?? 0,
    failed:     counts['failed']     ?? 0,
  });
}

// ─── POST /sync/offline-queue ─────────────────────────────────────────────────
// Batch-Nachsignierung ausstehender Offline-Bons.
// Verarbeitet bis zu BATCH_SIZE 'pending'-Einträge des Tenants.

export async function syncOfflineQueue(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const deviceId = req.auth!.deviceId;
  const userId   = req.auth!.userId;

  // Stuck 'processing'-Einträge zurücksetzen (Crash-Recovery, UPDATE erlaubt)
  await db.execute(
    `UPDATE offline_queue
     SET status = 'pending', error_message = 'Reset nach processing-Timeout'
     WHERE tenant_id = ? AND status = 'processing'
       AND created_at < NOW() - INTERVAL ? MINUTE`,
    [tenantId, STUCK_THRESHOLD_MINUTES]
  );

  // Pending-Einträge laden mit TSE-Konfiguration des Original-Geräts
  const [entries] = await db.execute<any[]>(
    `SELECT q.id, q.device_id, q.order_id, q.idempotency_key, q.payload_json, q.retry_count,
            d.tse_client_id,
            t.fiskaly_tss_id
     FROM offline_queue q
     JOIN devices d ON d.id = q.device_id AND d.tenant_id = q.tenant_id
     JOIN tenants t ON t.id = q.tenant_id
     WHERE q.tenant_id = ? AND q.status = 'pending'
     ORDER BY q.created_at ASC
     LIMIT ?`,
    [tenantId, BATCH_SIZE]
  );

  const result = { processed: 0, succeeded: 0, failed: 0 };

  for (const entry of entries) {
    // Als 'processing' markieren (UPDATE erlaubt)
    await db.execute(
      `UPDATE offline_queue SET status = 'processing' WHERE id = ? AND tenant_id = ?`,
      [entry.id, tenantId]
    );

    const payload = typeof entry.payload_json === 'string'
      ? JSON.parse(entry.payload_json)
      : entry.payload_json;

    result.processed++;

    // Kein receipt_id → Zahlung wurde nie abgeschlossen, TSE-TX wäre waisig
    if (!payload.receipt_id) {
      await db.execute(
        `UPDATE offline_queue
         SET status = 'failed', retry_count = retry_count + 1,
             error_message = 'Keine receipt_id — Zahlung nicht abgeschlossen'
         WHERE id = ? AND tenant_id = ?`,
        [entry.id, tenantId]
      );
      result.failed++;
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
          deviceId,
        }).catch(() => {});

      } else {
        // TSE noch nicht erreichbar — Eintrag zurück auf failed (erneut pending setzen für Retry möglich)
        await db.execute(
          `UPDATE offline_queue
           SET status = 'failed', retry_count = retry_count + 1,
               error_message = 'TSE nicht erreichbar'
           WHERE id = ? AND tenant_id = ?`,
          [entry.id, tenantId]
        );
        result.failed++;
      }

    } catch (err: any) {
      // 4xx / unerwarteter Fehler — als failed markieren
      await db.execute(
        `UPDATE offline_queue
         SET status = 'failed', retry_count = retry_count + 1,
             error_message = ?
         WHERE id = ? AND tenant_id = ?`,
        [(err.message ?? String(err)).slice(0, 500), entry.id, tenantId]
      );
      result.failed++;
    }
  }

  // Verbleibende pending-Einträge zählen (für Client-Info ob erneuter Aufruf nötig)
  const [[{ remaining }]] = await db.execute<any[]>(
    `SELECT COUNT(*) AS remaining FROM offline_queue WHERE tenant_id = ? AND status = 'pending'`,
    [tenantId]
  ) as any;

  res.json({ ...result, pending_remaining: Number(remaining) });
}

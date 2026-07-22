import { Request, Response } from 'express';
import { db } from '../db/index.js';
import { syncOfflineQueueForTenant, countPendingEntries } from '../services/offlineSync.js';

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
// Batch-Nachsignierung ausstehender Offline-Bons. Die Logik liegt in
// services/offlineSync.ts — denselben Pfad nutzt der stündliche Cron-Drain (S07),
// damit die Nachsignierung nicht davon abhängt, dass das iPad wiederkommt.

export async function syncOfflineQueue(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;

  const result = await syncOfflineQueueForTenant({ tenantId, userId });

  res.json({ ...result, pending_remaining: await countPendingEntries(tenantId) });
}

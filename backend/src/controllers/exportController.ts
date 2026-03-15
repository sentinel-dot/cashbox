import { Request, Response } from 'express';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db/index.js';
import {
  triggerDsfinvkExport,
  getDsfinvkExportStatus,
  getDsfinvkFileUrl,
  getFiskalyToken,
  type ExportState,
} from '../services/fiskaly.js';

// ─── Schema ───────────────────────────────────────────────────────────────────

const exportQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
  to:   z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
});

// ─── Polling-Hilfsfunktion ────────────────────────────────────────────────────

const TERMINAL_STATES: ExportState[] = ['COMPLETED', 'ERROR', 'CANCELLED'];

async function pollExport(
  tssId: string,
  exportId: string,
  maxMs = 8_000,
  intervalMs = 1_500,
): Promise<{ state: ExportState; exception: string | null }> {
  const deadline = Date.now() + maxMs;
  while (Date.now() < deadline) {
    const status = await getDsfinvkExportStatus(tssId, exportId);
    if (TERMINAL_STATES.includes(status.state)) {
      return { state: status.state, exception: status.exception };
    }
    await new Promise(r => setTimeout(r, intervalMs));
  }
  return { state: 'PENDING', exception: null }; // Timeout — noch nicht fertig
}

// ─── GET /export/dsfinvk?from=&to= ───────────────────────────────────────────
//
// Flow:
//   1. Fiskaly-Export triggern (PUT)
//   2. Bis zu 8s pollen — viele kleine Exporte sind sofort fertig
//   3a. COMPLETED → TAR-Datei über Fiskaly proxyen (Content-Type: application/x-tar)
//   3b. Noch nicht fertig → 202 + export_id (Client kann /:exportId/status + /:exportId/file nutzen)
//   4. ERROR/CANCELLED → 502 mit Fehlermeldung

export async function triggerExport(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const parsed = exportQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(422).json({ error: 'Validierungsfehler.', details: parsed.error.flatten().fieldErrors });
    return;
  }
  const { from, to } = parsed.data;

  if (from > to) {
    res.status(422).json({ error: 'from darf nicht nach to liegen.' });
    return;
  }

  // TSS-ID des Tenants laden
  const [tenantRows] = await db.execute<any[]>(
    'SELECT fiskaly_tss_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  const tssId: string | null = tenantRows[0]?.fiskaly_tss_id ?? null;

  if (!tssId) {
    res.status(503).json({ error: 'TSE nicht konfiguriert. Bitte Onboarding abschließen.' });
    return;
  }

  const exportId = uuidv4();

  // start_date = Beginn des from-Tages (00:00:00 UTC)
  // end_date   = Ende des to-Tages   (23:59:59 UTC)
  const startDate = new Date(`${from}T00:00:00Z`);
  const endDate   = new Date(`${to}T23:59:59Z`);

  await triggerDsfinvkExport(tssId, exportId, startDate, endDate);

  // Kurz pollen — kleine Tenants sind oft sofort fertig
  const { state, exception } = await pollExport(tssId, exportId);

  if (state === 'ERROR' || state === 'CANCELLED') {
    res.status(502).json({
      error:     'Fiskaly Export fehlgeschlagen.',
      exception: exception ?? 'Unbekannter Fehler',
      export_id: exportId,
    });
    return;
  }

  if (state === 'COMPLETED') {
    // TAR-Datei direkt zu Client proxyen
    await proxyExportFile(tssId, exportId, from, to, res);
    return;
  }

  // Noch PENDING/WORKING — Client soll später nachfragen
  res.status(202).json({
    message:   'Export wurde gestartet und wird verarbeitet. Status unter /:exportId/status abrufen.',
    export_id: exportId,
    tss_id:    tssId,
    from,
    to,
  });
}

// ─── GET /export/dsfinvk/:exportId/status ────────────────────────────────────

export async function getExportStatus(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const exportId = String(req.params['exportId']);

  const [tenantRows] = await db.execute<any[]>(
    'SELECT fiskaly_tss_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  const tssId: string | null = tenantRows[0]?.fiskaly_tss_id ?? null;

  if (!tssId) {
    res.status(503).json({ error: 'TSE nicht konfiguriert.' });
    return;
  }

  const status = await getDsfinvkExportStatus(tssId, exportId);

  res.json({
    export_id:       status.exportId,
    state:           status.state,
    exception:       status.exception,
    time_expiration: status.timeExpiration,
    download_ready:  status.state === 'COMPLETED',
  });
}

// ─── GET /export/dsfinvk/:exportId/file ──────────────────────────────────────

export async function downloadExportFile(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const exportId = String(req.params['exportId']);

  const [tenantRows] = await db.execute<any[]>(
    'SELECT fiskaly_tss_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  const tssId: string | null = tenantRows[0]?.fiskaly_tss_id ?? null;

  if (!tssId) {
    res.status(503).json({ error: 'TSE nicht konfiguriert.' });
    return;
  }

  // Status prüfen bevor Download
  const status = await getDsfinvkExportStatus(tssId, exportId);
  if (status.state !== 'COMPLETED') {
    res.status(409).json({
      error: `Export noch nicht abgeschlossen (Status: ${status.state}).`,
      state: status.state,
    });
    return;
  }

  await proxyExportFile(tssId, exportId, null, null, res);
}

// ─── Datei-Proxy (intern) ─────────────────────────────────────────────────────

async function proxyExportFile(
  tssId: string,
  exportId: string,
  from: string | null,
  to: string | null,
  res: Response,
): Promise<void> {
  const fileUrl = getDsfinvkFileUrl(tssId, exportId);
  const token   = await getFiskalyToken();

  const upstream = await fetch(fileUrl, {
    headers: { 'Authorization': `Bearer ${token}` },
  });

  if (!upstream.ok) {
    res.status(502).json({ error: `Fiskaly Dateidownload fehlgeschlagen: ${upstream.status}` });
    return;
  }

  const filename = from && to
    ? `dsfinvk_${from}_${to}.tar`
    : `dsfinvk_${exportId}.tar`;

  res.setHeader('Content-Type', 'application/x-tar');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  if (!upstream.body) {
    res.status(502).json({ error: 'Keine Datei von Fiskaly erhalten.' });
    return;
  }

  // Node-fetch ReadableStream → Express Response pipen
  const reader = upstream.body.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      res.write(value);
    }
    res.end();
  } finally {
    reader.releaseLock();
  }
}

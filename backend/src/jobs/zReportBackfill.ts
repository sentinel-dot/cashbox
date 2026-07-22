// Stündlich: geschlossene Sitzungen ohne Z-Bericht finden und nachtragen (A9).
//
// Warum es diese Lücke überhaupt gibt: `z_reports` wird von audit_insert_user
// geschrieben (INSERT-only, GoBD) — ein anderer DB-User als die Zahlungs-TX,
// also keine gemeinsame Transaktion möglich. Scheitert der INSERT nach dem
// Commit, ist die Sitzung geschlossen und der Tagesabschluss fehlt. Die Daten
// dafür sind vollständig da (payments/receipts sind unveränderlich), der Bericht
// ist also exakt rekonstruierbar — und genau das macht dieser Job, sichtbar
// markiert als Nachtrag.
import { db, auditDb } from '../db/index.js';
import { logger } from '../logger.js';
import { captureException } from '../sentry.js';
import { writeAuditLog } from '../services/audit.js';
import { buildZReportData, composeZReportJson } from '../controllers/sessionsController.js';
import type { JobResult } from './shared.js';

// Karenz: closeSession schreibt den Z-Bericht erst nach dem Commit der
// Schließen-TX. Ohne Karenz würde der Cron einer laufenden Schließung
// zuvorkommen und den Bericht doppelt anlegen wollen.
const SETTLE_MINUTES = 5;
const BACKFILL_BATCH_SIZE = 25;

export async function runZReportBackfill(): Promise<JobResult> {
  const [rows] = await db.execute<any[]>(
    `SELECT s.id, s.tenant_id, s.closed_at,
            s.opening_cash_cents, s.closing_cash_cents,
            s.expected_cash_cents, s.difference_cents
       FROM cash_register_sessions s
       LEFT JOIN z_reports z ON z.session_id = s.id AND z.tenant_id = s.tenant_id
      WHERE s.status = 'closed'
        AND s.closed_at IS NOT NULL
        AND s.closed_at < NOW() - INTERVAL ? MINUTE
        AND z.id IS NULL
      ORDER BY s.closed_at ASC
      LIMIT ?`,
    [SETTLE_MINUTES, BACKFILL_BATCH_SIZE]
  );

  const result = { missing: rows.length, backfilled: 0, skipped: 0 };

  for (const session of rows) {
    // Die Sitzung ist geschlossen: es kann keine Zahlung mehr hineinbuchen
    // (Session-Lock-Invariante), die Aggregation ist also stabil.
    const reportData = await buildZReportData(session.id, session.tenant_id);

    const zReportJson = composeZReportJson({
      sessionId:           session.id,
      tenantId:            session.tenant_id,
      closedAt:            new Date(session.closed_at),
      opening_cash_cents:  session.opening_cash_cents,
      closing_cash_cents:  session.closing_cash_cents,
      expected_cash_cents: session.expected_cash_cents,
      difference_cents:    session.difference_cents,
      reportData,
      reconstructed: {
        at: new Date(),
        reason: 'Nachtrag durch Cron: z_reports-Eintrag fehlte nach dem Schließen der Sitzung',
      },
    });

    try {
      const [insert] = await auditDb.execute<any>(
        `INSERT INTO z_reports (session_id, tenant_id, report_json) VALUES (?, ?, ?)`,
        [session.id, session.tenant_id, JSON.stringify(zReportJson)]
      );
      result.backfilled++;

      await writeAuditLog({
        tenantId:   session.tenant_id,
        userId:     null,
        action:     'session.z_report_backfilled',
        entityType: 'cash_register_session',
        entityId:   session.id,
        diff:       { new: { z_report_id: insert.insertId, closed_at: session.closed_at } },
      });

      // Nachgetragen ist nicht „erledigt": dass der INSERT beim Schließen
      // fehlschlug, bleibt ein Vorfall, den jemand ansehen muss.
      logger.error(
        { tenant: session.tenant_id, session: session.id, z_report: insert.insertId },
        'Z-Bericht fehlte und wurde nachgetragen — Ursache des fehlgeschlagenen INSERTs prüfen'
      );
      captureException(
        new Error(`Z-Bericht für Sitzung ${session.id} fehlte und wurde nachgetragen`),
        { tenant: session.tenant_id, source: 'cron:z-report-backfill' }
      );
    } catch (err: any) {
      // UNIQUE(session_id) aus V012: ein paralleler Schreiber war schneller.
      // Kein Fehler, sondern der Beweis, dass der Backstop greift.
      if (err?.errno === 1062) {
        result.skipped++;
        continue;
      }
      throw err;
    }
  }

  return result;
}

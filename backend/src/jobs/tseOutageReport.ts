// Stündlich: TSE-Ausfälle, die länger als 48 h dauern.
//
// § 146a AO / KassenSichV: Ein Ausfall der TSE ist unverzüglich zu dokumentieren
// und, wenn er nicht kurzfristig behoben wird, dem Finanzamt zu melden. Die
// Meldung selbst macht der Betreiber über ELSTER — die Software schuldet ihm den
// rechtzeitigen, belegten Hinweis. `notified_at` ist der Nachweis, dass er ihn
// bekommen hat, und zugleich der Idempotenz-Marker.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { captureException } from '../sentry.js';
import { sendTseOutageAlert } from '../services/email/index.js';
import { ownerRecipient, type JobResult } from './shared.js';

const OUTAGE_REPORT_THRESHOLD_HOURS = 48;

export async function runTseOutageReport(): Promise<JobResult> {
  const [rows] = await db.execute<any[]>(
    `SELECT o.id, o.tenant_id, o.device_id, o.started_at, d.name AS device_name
       FROM tse_outages o
       JOIN devices d ON d.id = o.device_id AND d.tenant_id = o.tenant_id
      WHERE o.ended_at   IS NULL
        AND o.notified_at IS NULL
        AND o.started_at < NOW() - INTERVAL ? HOUR`,
    [OUTAGE_REPORT_THRESHOLD_HOURS]
  );

  const result = { found: rows.length, queued: 0, skipped: 0, no_recipient: 0 };
  const observedAt = new Date();

  for (const outage of rows) {
    const owner = await ownerRecipient(outage.tenant_id);
    if (!owner) {
      result.no_recipient++;
      // Kein Empfänger heißt hier: meldepflichtiger Ausfall ohne Adressat.
      // Das darf nicht nur im Log stehen.
      captureException(
        new Error(`TSE-Ausfall > 48 h ohne Empfänger (Tenant ${outage.tenant_id}, Ausfall ${outage.id})`),
        { tenant: outage.tenant_id, source: 'cron:tse-outage-report' }
      );
      continue;
    }

    const queued = await sendTseOutageAlert({
      tenantId:        outage.tenant_id,
      tenantName:      owner.tenantName,
      recipient:       owner.email,
      outageId:        outage.id,
      deviceName:      outage.device_name,
      outageStartedAt: new Date(outage.started_at),
      observedAt,
    });

    // Marker erst NACH dem Einreihen setzen: schlägt das UPDATE fehl, meldet der
    // nächste Lauf erneut — und die Queue verwirft die Dublette am UNIQUE-Key.
    // Andersherum wäre eine Pflichtmeldung still verloren.
    const [update] = await db.execute<any>(
      `UPDATE tse_outages SET notified_at = NOW() WHERE id = ? AND notified_at IS NULL`,
      [outage.id]
    );

    if (queued) result.queued++; else result.skipped++;

    if (update.affectedRows === 1) {
      logger.error(
        { tenant: outage.tenant_id, device: outage.device_id, outage: outage.id, started_at: outage.started_at },
        'TSE-Ausfall länger als 48 h — Meldepflicht, Owner benachrichtigt'
      );
      captureException(
        new Error(`TSE-Ausfall > 48 h (Tenant ${outage.tenant_id}, Gerät ${outage.device_id})`),
        { tenant: outage.tenant_id, source: 'cron:tse-outage-report' }
      );
    }
  }

  return result;
}

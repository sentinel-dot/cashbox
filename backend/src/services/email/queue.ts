// Retry-Queue für E-Mails. Muster wie offline_queue: atomarer Claim per UPDATE,
// Stuck-Reset über processing_started_at (V006-Begründung gilt hier genauso),
// Exponential-Backoff statt Endlosschleife.
//
// Warum überhaupt eine Queue: Die KassenSichV-Meldemail (TSE-Ausfall > 48 h) darf
// nicht verloren gehen, weil Resend gerade 500 liefert. Und kein Aufrufer soll auf
// einen HTTP-Call zu einem Drittanbieter warten — enqueue ist ein INSERT.
import type { RowDataPacket } from 'mysql2/promise';
import { db, auditDb } from '../../db/index.js';
import { logger } from '../../logger.js';
import { captureException } from '../../sentry.js';
import { sendMail, type SendInput, type SendResult } from './send.js';
import { renderTemplate, type TemplateName, type TemplateData } from './templates.js';

/** Nach `attempts` Fehlversuchen: 1→1min, 2→5min, 3→15min, 4→1h, 5→4h (Deckel). */
export function backoffMinutes(attempts: number): number {
  const table = [1, 5, 15, 60, 240];
  return table[Math.min(Math.max(attempts, 1), table.length) - 1]!;
}

/** Claim gilt als hängend, wenn er älter ist als das (Prozess-Crash mitten im Versand). */
const STUCK_THRESHOLD_MINUTES = 10;

export type EnqueueInput<K extends TemplateName = TemplateName> = {
  /** NULL nur für System-Mails ohne Tenant-Bezug. */
  tenantId: number | null;
  template: K;
  data: TemplateData[K];
  recipient: string;
  replyTo?: string;
  /** Stabiler Schlüssel gegen Doppelversand, z.B. `trial_warning:42:day10`.
   *  Ein zweiter Lauf desselben Cron-Jobs legt dann keine zweite Mail an. */
  idempotencyKey: string;
};

/**
 * Rendert das Template und legt die Mail in die Queue. Kein Versand hier —
 * der passiert im Drain (Cron, S07). Rückgabe: false, wenn der
 * idempotency_key schon existierte (= bereits eingereiht, kein Fehler).
 */
export async function enqueueMail<K extends TemplateName>(
  input: EnqueueInput<K>
): Promise<boolean> {
  const mail = renderTemplate(input.template, input.data);

  // INSERT IGNORE statt Vorab-SELECT: der UNIQUE-Key entscheidet, kein Race-Fenster.
  const [result] = await db.execute<any>(
    `INSERT IGNORE INTO email_queue
       (tenant_id, template, recipient, reply_to, subject, body_html, body_text, idempotency_key)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      input.tenantId,
      input.template,
      input.recipient,
      input.replyTo ?? null,
      mail.subject,
      mail.html,
      mail.text,
      input.idempotencyKey,
    ]
  );

  const inserted = result.affectedRows === 1;
  if (!inserted) {
    logger.debug(
      { template: input.template, idempotencyKey: input.idempotencyKey },
      'E-Mail bereits eingereiht — übersprungen'
    );
  }
  return inserted;
}

type QueueRow = {
  id: number;
  tenant_id: number | null;
  template: string;
  recipient: string;
  reply_to: string | null;
  subject: string | null;
  body_html: string | null;
  body_text: string | null;
  attempts: number;
  max_attempts: number;
};

export type DrainResult = { sent: number; failed: number; retry: number };

/**
 * Verarbeitet alle fälligen Zeilen. Idempotent und nebenläufig sicher: jede Zeile
 * wird per bedingtem UPDATE geclaimt, ein paralleler Lauf bekommt affectedRows = 0.
 * `sender` ist injizierbar, damit Tests den Retry-Pfad ohne Netz prüfen können.
 */
export async function drainEmailQueue(
  max = 25,
  sender: (input: SendInput) => Promise<SendResult> = sendMail
): Promise<DrainResult> {
  const result: DrainResult = { sent: 0, failed: 0, retry: 0 };

  // Crash-Recovery: hängende Claims wieder freigeben (UPDATE auf operativen
  // Zustandsfeldern ist erlaubt — email_queue ist keine Finanztabelle).
  await db.execute(
    `UPDATE email_queue
        SET status = 'pending'
      WHERE status = 'processing'
        AND processing_started_at IS NOT NULL
        AND processing_started_at < NOW() - INTERVAL ? MINUTE`,
    [STUCK_THRESHOLD_MINUTES]
  );

  for (let i = 0; i < max; i++) {
    const [dueRows] = await db.execute<any[]>(
      `SELECT id FROM email_queue
        WHERE status = 'pending' AND next_attempt_at <= NOW()
        ORDER BY next_attempt_at
        LIMIT 1`
    );
    const due = dueRows[0];
    if (!due) break;

    const [claim] = await db.execute<any>(
      `UPDATE email_queue
          SET status = 'processing', processing_started_at = NOW(), attempts = attempts + 1
        WHERE id = ? AND status = 'pending'`,
      [due.id]
    );
    if (claim.affectedRows !== 1) continue; // anderer Drain war schneller

    const [rows] = await db.execute<(QueueRow & RowDataPacket)[]>(
      `SELECT id, tenant_id, template, recipient, reply_to, subject,
              body_html, body_text, attempts, max_attempts
         FROM email_queue WHERE id = ?`,
      [due.id]
    );
    const row = rows[0];
    if (!row) continue;

    try {
      const sendResult = await sender({
        to: row.recipient,
        subject: row.subject ?? '',
        html: row.body_html ?? '',
        text: row.body_text ?? '',
        replyTo: row.reply_to ?? undefined,
      });

      // Nachweis zuerst (INSERT-only, audit_insert_user): Wenn der Log-INSERT
      // scheitert, bleibt die Zeile 'processing' und läuft nach dem Stuck-Reset
      // erneut — lieber eine Mail doppelt als eine Pflichtmeldung ohne Nachweis.
      await auditDb.execute(
        `INSERT INTO email_log
           (tenant_id, template, recipient, subject, provider_message_id)
         VALUES (?, ?, ?, ?, ?)`,
        [row.tenant_id, row.template, row.recipient, row.subject ?? '', sendResult.providerMessageId]
      );

      // Erfolg: Inhalte nullen — Empfängerinhalte gehören nicht dauerhaft in die
      // Betriebs-DB (DSGVO-Datenminimierung). Der Nachweis steht in email_log.
      await db.execute(
        `UPDATE email_queue
            SET status = 'sent', sent_at = NOW(),
                subject = NULL, body_html = NULL, body_text = NULL, last_error = NULL
          WHERE id = ?`,
        [row.id]
      );
      result.sent++;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);

      if (row.attempts >= row.max_attempts) {
        await db.execute(
          `UPDATE email_queue SET status = 'failed', last_error = ? WHERE id = ?`,
          [msg.slice(0, 500), row.id]
        );
        result.failed++;
        logger.error(
          { mailId: row.id, template: row.template, err: msg },
          'E-Mail endgültig fehlgeschlagen'
        );
        // Endgültig verlorene Mail ist ein Betriebsvorfall (kann eine
        // KassenSichV-Meldung sein) — nicht nur ins Log, sondern nach Sentry.
        captureException(err instanceof Error ? err : new Error(msg), {
          tenant: row.tenant_id ?? undefined,
          source: `email-queue:${row.template}`,
        });
      } else {
        await db.execute(
          `UPDATE email_queue
              SET status = 'pending',
                  next_attempt_at = NOW() + INTERVAL ? MINUTE,
                  last_error = ?
            WHERE id = ?`,
          [backoffMinutes(row.attempts), msg.slice(0, 500), row.id]
        );
        result.retry++;
        logger.warn(
          { mailId: row.id, template: row.template, attempts: row.attempts, err: msg },
          'E-Mail-Versand fehlgeschlagen — Retry eingeplant'
        );
      }
    }
  }

  return result;
}

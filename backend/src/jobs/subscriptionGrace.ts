// Täglich: Tenants, deren Kulanzfrist nach `past_due` abgelaufen ist.
//
// Bewusste Entscheidung (S07): Dieser Job SPERRT NICHT selbst. Die Sperre sitzt
// weiterhin in der subscriptionMiddleware, die bei jedem Request gegen dieselben
// Konstanten prüft (services/subscription.ts) — ein Cron-Job, der zusätzlich
// `subscription_status` umschreibt, würde Stripe als alleinige Quelle des
// Abo-Status entwerten und dem Wirt „gekündigt" schreiben, wo nur eine Zahlung
// fehlgeschlagen ist. Der Job macht das Ereignis sichtbar: Mail an den Owner,
// audit_log-Eintrag, Sentry-Alert. Ablösung durch die Entitlement-Matrix: S17C.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { captureException } from '../sentry.js';
import { sendSubscriptionEvent } from '../services/email/index.js';
import { writeAuditLog } from '../services/audit.js';
import { GRACE_PERIOD_DAYS } from '../services/subscription.js';
import { ownerRecipient, type JobResult } from './shared.js';

export async function runSubscriptionGrace(): Promise<JobResult> {
  const [rows] = await db.execute<any[]>(
    `SELECT id, name, subscription_current_period_end
       FROM tenants
      WHERE subscription_status = 'past_due'
        AND subscription_current_period_end IS NOT NULL
        AND subscription_current_period_end < NOW() - INTERVAL ? DAY`,
    [GRACE_PERIOD_DAYS]
  );

  const result = { expired: rows.length, queued: 0, skipped: 0, no_recipient: 0 };

  for (const tenant of rows) {
    // Ein Marker pro Abrechnungszeitraum: zahlt der Kunde und fällt später erneut
    // aus, ist der Zeitraum ein anderer → neue Mail. Derselbe Zeitraum → nie zweimal.
    const periodEnd = new Date(tenant.subscription_current_period_end);
    const marker = `grace_expired:${periodEnd.toISOString().slice(0, 10)}`;

    const owner = await ownerRecipient(tenant.id);
    if (!owner) {
      result.no_recipient++;
      logger.warn({ tenant: tenant.id }, 'Grace-Period abgelaufen, aber kein aktiver Owner als Empfänger');
      continue;
    }

    const queued = await sendSubscriptionEvent({
      tenantId:    tenant.id,
      recipient:   owner.email,
      eventMarker: marker,
      event:       'past_due',
      tenantName:  owner.tenantName,
    });

    if (!queued) { result.skipped++; continue; }
    result.queued++;

    // Nur beim erstmaligen Auslösen protokollieren — sonst wächst das audit_log
    // (INSERT-only!) täglich um denselben Sachverhalt.
    await writeAuditLog({
      tenantId:   tenant.id,
      userId:     null,
      action:     'subscription.grace_expired',
      entityType: 'tenant',
      entityId:   tenant.id,
      diff:       { new: { grace_period_days: GRACE_PERIOD_DAYS, period_end: periodEnd.toISOString() } },
    });

    logger.warn(
      { tenant: tenant.id, period_end: periodEnd.toISOString() },
      'Kulanzfrist abgelaufen — Zugriff wird von der subscriptionMiddleware gesperrt'
    );
    captureException(
      new Error(`Kulanzfrist abgelaufen (Tenant ${tenant.id}) — Zugriff gesperrt`),
      { tenant: tenant.id, source: 'cron:subscription-grace' }
    );
  }

  return result;
}

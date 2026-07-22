// Täglich: Trial-Warnung an Tag 10 und Tag 13 des 14-Tage-Trials.
import { db } from '../db/index.js';
import { logger } from '../logger.js';
import { sendTrialWarning } from '../services/email/index.js';
import { TRIAL_DAYS, TRIAL_WARNING_DAYS, trialExpiresAt, trialWarningMarker } from '../services/subscription.js';
import { ownerRecipient, type JobResult } from './shared.js';

const FIRST_WARNING_DAY = Math.min(...TRIAL_WARNING_DAYS);

export async function runTrialWarnings(): Promise<JobResult> {
  // Vorfilter in SQL (Tenants im Warnfenster), Entscheidung in der puren
  // trialWarningMarker() — die kennt als einzige Stelle die Schwellen.
  const [rows] = await db.execute<any[]>(
    `SELECT id, name, created_at, DATEDIFF(NOW(), created_at) AS age_days
       FROM tenants
      WHERE subscription_status = 'trial'
        AND created_at <= NOW() - INTERVAL ? DAY
        AND created_at >  NOW() - INTERVAL ? DAY`,
    [FIRST_WARNING_DAY, TRIAL_DAYS]
  );

  const result = { checked: rows.length, queued: 0, skipped: 0, no_recipient: 0 };

  for (const tenant of rows) {
    const marker = trialWarningMarker(Number(tenant.age_days));
    if (!marker) { result.skipped++; continue; }

    const owner = await ownerRecipient(tenant.id);
    if (!owner) {
      result.no_recipient++;
      logger.warn({ tenant: tenant.id }, 'Trial-Warnung ohne Empfänger — kein aktiver Owner');
      continue;
    }

    // Doppelversand verhindert der Idempotenz-Schlüssel in enqueueMail;
    // `false` heißt hier nur „stand schon in der Queue", nicht „Fehler".
    const queued = await sendTrialWarning({
      tenantId:    tenant.id,
      tenantName:  owner.tenantName,
      recipient:   owner.email,
      trialEndsAt: trialExpiresAt(new Date(tenant.created_at)),
      dayMarker:   marker,
    });
    if (queued) result.queued++; else result.skipped++;
  }

  return result;
}

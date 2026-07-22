// Abo-Fristen an EINER Stelle: subscriptionMiddleware (Sperre zur Request-Zeit)
// und die Cron-Jobs aus S07 (Warnmails) müssen zwingend dieselben Grenzen benutzen —
// sonst warnt die Mail an Tag 13, während die Kasse schon 402 liefert.
//
// Achtung S17C: Dort wird das Trial-Modell umgebaut (trial_started_at/-expires_at
// statt created_at + Entitlement-Matrix). Dann ist DIESE Datei der Ort dafür.

export const TRIAL_DAYS = 14;
export const GRACE_PERIOD_DAYS = 3;

/** Vorwarnungen: 4 Tage und 1 Tag vor Ablauf des 14-Tage-Trials. */
export const TRIAL_WARNING_DAYS = [10, 13] as const;

export type TrialWarningMarker = 'day10' | 'day13';

/** Ende des Trials — heute abgeleitet aus `tenants.created_at`. */
export function trialExpiresAt(createdAt: Date, trialDays = TRIAL_DAYS): Date {
  const expiry = new Date(createdAt);
  expiry.setDate(expiry.getDate() + trialDays);
  return expiry;
}

/** Ende der Kulanzfrist nach `past_due` — danach sperrt die Middleware. */
export function graceEndsAt(periodEnd: Date, graceDays = GRACE_PERIOD_DAYS): Date {
  const end = new Date(periodEnd);
  end.setDate(end.getDate() + graceDays);
  return end;
}

/**
 * Welche Trial-Warnung ist bei diesem Tenant-Alter fällig?
 *
 * Bewusst als Schwelle (`>=`) und nicht als exakter Tag: fällt der Cron-Lauf an
 * Tag 10 aus, bekommt der Wirt die Warnung an Tag 11 — statt gar nicht. Doppelte
 * Mails verhindert der Idempotenz-Schlüssel (`trial_warning:<tenant>:day10`),
 * nicht diese Funktion. Nach Ablauf (Tag 14+) wird nicht mehr gewarnt, dann
 * greift die Sperre der subscriptionMiddleware.
 */
export function trialWarningMarker(
  ageDays: number,
  trialDays = TRIAL_DAYS
): TrialWarningMarker | null {
  if (ageDays >= trialDays) return null;
  if (ageDays >= 13) return 'day13';
  if (ageDays >= 10) return 'day10';
  return null;
}

// Öffentliche Mail-Schnittstelle: eine Funktion pro Anlass. Aufrufer (Cron aus S07,
// Controller) rufen NUR diese Funktionen — sie rendern, reihen ein und kehren sofort
// zurück. Kein Aufrufer wartet auf einen Drittanbieter-HTTP-Call.
import { enqueueMail } from './queue.js';

export { enqueueMail, drainEmailQueue, backoffMinutes } from './queue.js';
export { renderTemplate, templates, type TemplateName, type TemplateData, type BuiltMail } from './templates.js';
export { isDryRun } from './send.js';

function appUrl(): string {
  return (process.env['APP_URL'] ?? 'https://app.cashbox.de').replace(/\/$/, '');
}

/**
 * Trial-Warnung (Tag 10 + 13 des 14-Tage-Tests, OFFEN.md §5 Template 1).
 * `dayMarker` geht in den Idempotenz-Schlüssel: derselbe Cron-Lauf am selben Tag
 * legt keine zweite Mail an, Tag 10 und Tag 13 sind aber zwei eigene Mails.
 */
export async function sendTrialWarning(input: {
  tenantId: number;
  tenantName: string;
  recipient: string;
  trialEndsAt: Date;
  dayMarker: 'day10' | 'day13';
}): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'trial_warning',
    recipient: input.recipient,
    idempotencyKey: `trial_warning:${input.tenantId}:${input.dayMarker}`,
    data: {
      tenantName: input.tenantName,
      trialEndsAt: input.trialEndsAt,
      upgradeUrl: `${appUrl()}/abo`,
    },
  });
}

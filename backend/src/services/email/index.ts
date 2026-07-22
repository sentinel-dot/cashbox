// Öffentliche Mail-Schnittstelle: eine Funktion pro Anlass. Aufrufer (Cron aus S07,
// Controller aus S08) rufen NUR diese Funktionen — sie rendern, reihen ein und
// kehren sofort zurück. Kein Aufrufer wartet auf einen Drittanbieter-HTTP-Call.
import { enqueueMail } from './queue.js';
import type { SubscriptionEventData, TemplateName } from './templates.js';

export { enqueueMail, drainEmailQueue, backoffMinutes } from './queue.js';
export {
  renderTemplate,
  templates,
  type TemplateName,
  type TemplateData,
  type BuiltMail,
  type PaymentSummary,
  type SubscriptionEventData,
} from './templates.js';
export { isDryRun } from './send.js';

function appUrl(): string {
  return (process.env['APP_URL'] ?? 'https://app.cashbox.de').replace(/\/$/, '');
}

/** Pure, deterministisch und ohne Empfänger-/Tokenwerte. */
export function emailIdempotencyKey(
  template: TemplateName,
  tenantId: number,
  marker: string | number
): string {
  return `${template}:${tenantId}:${marker}`;
}

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
    idempotencyKey: emailIdempotencyKey('trial_warning', input.tenantId, input.dayMarker),
    data: {
      tenantName: input.tenantName,
      trialEndsAt: input.trialEndsAt,
      upgradeUrl: `${appUrl()}/abo`,
    },
  });
}

export async function sendTseOutageAlert(input: {
  tenantId: number;
  tenantName: string;
  recipient: string;
  outageId: number;
  deviceName: string;
  outageStartedAt: Date;
  observedAt: Date;
}): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'tse_outage',
    recipient: input.recipient,
    idempotencyKey: emailIdempotencyKey('tse_outage', input.tenantId, `${input.outageId}:48h`),
    data: {
      tenantName: input.tenantName,
      deviceName: input.deviceName,
      outageStartedAt: input.outageStartedAt,
      observedAt: input.observedAt,
      elsterUrl: 'https://www.elster.de/eportal/start',
    },
  });
}

export async function sendPasswordReset(input: {
  tenantId: number;
  tenantName: string;
  recipient: string;
  requestId: string;
  resetUrl: string;
  expiresAt: Date;
}): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'password_reset',
    recipient: input.recipient,
    idempotencyKey: emailIdempotencyKey('password_reset', input.tenantId, input.requestId),
    data: {
      tenantName: input.tenantName,
      resetUrl: input.resetUrl,
      expiresAt: input.expiresAt,
    },
  });
}

export async function sendDailyZReport(input: {
  tenantId: number;
  tenantName: string;
  recipient: string;
  zReportId: number;
  reportDate: Date;
  totalRevenueCents: number;
  payments: Array<{ method: 'cash' | 'card'; amountCents: number }>;
  differenceCents: number;
}): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'daily_z_report',
    recipient: input.recipient,
    idempotencyKey: emailIdempotencyKey('daily_z_report', input.tenantId, input.zReportId),
    data: {
      tenantName: input.tenantName,
      reportDate: input.reportDate,
      totalRevenueCents: input.totalRevenueCents,
      payments: input.payments,
      differenceCents: input.differenceCents,
      reportUrl: `${appUrl()}/berichte/z/${input.zReportId}`,
    },
  });
}

type SendSubscriptionEventInput = {
  tenantId: number;
  recipient: string;
  /**
   * Anlass-Marker für die Idempotenz: die Stripe-Event-ID (`evt_…`) beim
   * Webhook, ein Cron-Anlass (`grace_expired:2026-07-01`) beim Cron-Job.
   * Derselbe Marker = dieselbe Mail, egal wie oft der Auslöser feuert.
   */
  eventMarker: string;
} & (
  | { event: 'past_due'; tenantName: string }
  | { event: 'cancelled'; tenantName: string; effectiveAt: Date }
  | { event: 'reactivated'; tenantName: string }
);

function subscriptionData(input: SendSubscriptionEventInput): SubscriptionEventData {
  if (input.event === 'past_due') {
    return { event: input.event, tenantName: input.tenantName, billingUrl: `${appUrl()}/abo` };
  }
  if (input.event === 'cancelled') {
    return {
      event: input.event,
      tenantName: input.tenantName,
      effectiveAt: input.effectiveAt,
      dataExportUrl: `${appUrl()}/export`,
    };
  }
  return { event: input.event, tenantName: input.tenantName, dashboardUrl: appUrl() };
}

export async function sendSubscriptionEvent(input: SendSubscriptionEventInput): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'subscription_event',
    recipient: input.recipient,
    idempotencyKey: emailIdempotencyKey('subscription_event', input.tenantId, input.eventMarker),
    data: subscriptionData(input),
  });
}

export async function sendLongOpenSessionWarning(input: {
  tenantId: number;
  tenantName: string;
  recipient: string;
  sessionId: number;
  deviceName: string;
  openedAt: Date;
  observedAt: Date;
}): Promise<boolean> {
  return enqueueMail({
    tenantId: input.tenantId,
    template: 'long_open_session',
    recipient: input.recipient,
    idempotencyKey: emailIdempotencyKey('long_open_session', input.tenantId, `${input.sessionId}:24h`),
    data: {
      tenantName: input.tenantName,
      deviceName: input.deviceName,
      openedAt: input.openedAt,
      observedAt: input.observedAt,
      sessionUrl: `${appUrl()}/kassensitzung`,
    },
  });
}

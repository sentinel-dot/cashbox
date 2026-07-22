// Registry aller Hintergrund-Jobs (S07, OFFEN.md B2).
//
// Die Zeitpläne sind Europe/Berlin (cron.ts setzt die Zone) und bewusst über die
// Stunde verteilt: laufen alle stündlichen Jobs zur vollen Minute 0, konkurrieren
// sie mit dem Kassenbetrieb um dieselben Zeilen (Sitzungen, Offline-Queue).
//
// Abweichung von der ursprünglichen Planung in ROADMAP.md S07: „Sitzung > 24 h
// offen" und „TSE-Ausfall > 48 h" laufen stündlich statt täglich. Beide Mails
// sind pro Vorfall idempotent (Idempotenz-Schlüssel bzw. notified_at), es gibt
// also keinen Spam-Effekt — aber eine Meldepflicht bis zu 24 h liegen zu lassen,
// wäre bei einem TSE-Ausfall grob fahrlässig.
import { drainEmailQueue } from '../services/email/queue.js';
import { runTrialWarnings } from './trialWarnings.js';
import { runSubscriptionGrace } from './subscriptionGrace.js';
import { runLongOpenSessions } from './longOpenSessions.js';
import { runTseOutageReport } from './tseOutageReport.js';
import { runOfflineQueueDrain } from './offlineQueueDrain.js';
import { runOfflineQueueAlerts } from './offlineQueueAlerts.js';
import { runZReportBackfill } from './zReportBackfill.js';
import type { JobDefinition, JobResult } from './shared.js';

export type { JobDefinition, JobResult } from './shared.js';

/** Versendet, was in der Queue liegt. Ohne diesen Job bleibt jede Mail liegen. */
export async function runEmailDrain(): Promise<JobResult> {
  const { sent, failed, retry } = await drainEmailQueue();
  return { sent, failed, retry };
}

export const jobs: JobDefinition[] = [
  {
    name: 'email-drain',
    schedule: '*/5 * * * *',
    description: 'Fällige E-Mails aus email_queue versenden (Backoff + email_log)',
    run: runEmailDrain,
  },
  {
    name: 'long-open-sessions',
    schedule: '10 * * * *',
    description: 'Kassensitzungen > 24 h offen → Owner-Mail (GoBD: täglicher Abschluss)',
    run: runLongOpenSessions,
  },
  {
    name: 'tse-outage-report',
    schedule: '15 * * * *',
    description: 'TSE-Ausfall > 48 h → Owner-Mail + notified_at (KassenSichV-Meldepflicht)',
    run: runTseOutageReport,
  },
  {
    name: 'offline-queue-drain',
    schedule: '20 * * * *',
    description: 'Serverseitige Nachsignierung offener Offline-Bons (unabhängig vom iPad)',
    run: runOfflineQueueDrain,
  },
  {
    name: 'offline-queue-alerts',
    schedule: '25 * * * *',
    description: 'Endgültig gescheiterte Queue-Einträge einmalig melden (alerted_at)',
    run: runOfflineQueueAlerts,
  },
  {
    name: 'z-report-backfill',
    schedule: '30 * * * *',
    description: 'Geschlossene Sitzungen ohne Z-Bericht nachtragen + melden (A9)',
    run: runZReportBackfill,
  },
  {
    name: 'trial-warnings',
    schedule: '0 6 * * *',
    description: 'Trial-Warnung an Tag 10 und Tag 13',
    run: runTrialWarnings,
  },
  {
    name: 'subscription-grace',
    schedule: '15 6 * * *',
    description: 'Abgelaufene Kulanzfrist nach past_due melden (Sperre: subscriptionMiddleware)',
    run: runSubscriptionGrace,
  },
];

export function findJob(name: string): JobDefinition | undefined {
  return jobs.find((job) => job.name === name);
}

export {
  runTrialWarnings,
  runSubscriptionGrace,
  runLongOpenSessions,
  runTseOutageReport,
  runOfflineQueueDrain,
  runOfflineQueueAlerts,
  runZReportBackfill,
};

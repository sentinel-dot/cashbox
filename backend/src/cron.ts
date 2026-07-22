// cron.ts
// cashbox — Zeitsteuerung der Hintergrund-Jobs (S07, OFFEN.md B2).
//
// Läuft im selben Prozess wie der API-Server (Start in index.ts). Das ist bewusst:
// PM2 fährt laut S20 eine einzelne Instanz, ein zweiter Prozess wäre nur eine
// weitere Sache, die man zu deployen vergessen kann. Ginge es später auf mehrere
// Instanzen, ist der Schutz trotzdem da — jeder Job claimt seine Zeilen atomar
// und dedupliziert über einen DB-Marker, ein Doppellauf erzeugt also keine
// zweite Mail und keinen zweiten Z-Bericht (`CRON_ENABLED=false` schaltet
// einzelne Instanzen zusätzlich stumm).
//
// Zeitzone: Europe/Berlin. „Täglich 6 Uhr" heißt für einen Gastronomen 6 Uhr
// Ortszeit, auch im Winter — der Server läuft aber (wie üblich) auf UTC.
import cron from 'node-cron';
import { logger } from './logger.js';
import { captureException } from './sentry.js';
import { jobs, type JobDefinition, type JobResult } from './jobs/index.js';

export const CRON_TIMEZONE = 'Europe/Berlin';

let scheduled: Array<{ name: string; task: ReturnType<typeof cron.schedule> }> = [];

/**
 * Führt einen Job aus und protokolliert Ergebnis bzw. Fehler.
 *
 * Ein geworfener Job darf den Prozess nicht mitreißen: unhandledRejection würde
 * laut index.ts den Server herunterfahren — ein fehlgeschlagener Warnmail-Job
 * hätte dann die Kasse abgeschaltet. Deshalb fängt der Wrapper alles und meldet
 * es an Sentry.
 */
export async function runJob(job: JobDefinition): Promise<JobResult | null> {
  const startedAt = Date.now();
  try {
    const result = await job.run();
    logger.info({ job: job.name, durationMs: Date.now() - startedAt, ...result }, 'Cron-Job abgeschlossen');
    return result;
  } catch (err) {
    logger.error({ err, job: job.name, durationMs: Date.now() - startedAt }, 'Cron-Job fehlgeschlagen');
    captureException(err, { source: `cron:${job.name}` });
    return null;
  }
}

/** Registriert alle Jobs. `CRON_ENABLED=false` lässt den Prozess ohne Jobs laufen. */
export function startCron(): void {
  if (process.env['CRON_ENABLED'] === 'false') {
    logger.info('Cron deaktiviert (CRON_ENABLED=false)');
    return;
  }
  if (scheduled.length > 0) return; // doppelter Start ist ein Programmierfehler, kein Grund für doppelte Timer

  for (const job of jobs) {
    const task = cron.schedule(job.schedule, () => runJob(job), {
      timezone: CRON_TIMEZONE,
      name: job.name,
      // Ein noch laufender Drain darf sich nicht selbst überholen.
      noOverlap: true,
    });
    scheduled.push({ name: job.name, task });
  }

  logger.info(
    { timezone: CRON_TIMEZONE, jobs: jobs.map((j) => `${j.name}@${j.schedule}`) },
    `Cron gestartet (${jobs.length} Jobs)`
  );
}

/** Stoppt alle Timer — Teil des geordneten Shutdowns (kein neuer Job beim Deploy). */
export async function stopCron(): Promise<void> {
  if (scheduled.length === 0) return;
  // destroy() statt stop(): der Task verschwindet aus der node-cron-Registry,
  // ein späterer startCron() (Tests, Neustart im selben Prozess) beginnt sauber.
  await Promise.allSettled(scheduled.map(({ task }) => task.destroy()));
  scheduled = [];
  logger.info('Cron gestoppt');
}

/** Namen der aktuell registrierten Jobs — für Tests und Diagnose. */
export function scheduledJobNames(): string[] {
  return scheduled.map((s) => s.name);
}

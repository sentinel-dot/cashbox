import { describe, it, expect, vi, afterEach } from 'vitest';
import cron from 'node-cron';
import { jobs, findJob } from '../../jobs/index.js';
import { runJob, startCron, stopCron, scheduledJobNames, CRON_TIMEZONE } from '../../cron.js';

// REQ-CRON-009 (UC-CRON-09): Die Zeitpläne sind Teil des Betriebs, nicht Deko.
// Ein Tippfehler im Cron-Ausdruck fällt sonst erst auf, wenn die Trial-Mail
// wochenlang nicht kam.

describe('Job-Registry', () => {
  it('hat für jeden Job einen gültigen Cron-Ausdruck', () => {
    for (const job of jobs) {
      expect(cron.validate(job.schedule), `${job.name}: ${job.schedule}`).toBe(true);
    }
  });

  it('vergibt eindeutige Namen (CLI und Logs referenzieren sie)', () => {
    const names = jobs.map((j) => j.name);
    expect(new Set(names).size).toBe(names.length);
  });

  it('enthält alle in S07 zugesagten Jobs', () => {
    expect(jobs.map((j) => j.name).sort()).toEqual([
      'email-drain',
      'long-open-sessions',
      'offline-queue-alerts',
      'offline-queue-drain',
      'subscription-grace',
      'trial-warnings',
      'tse-outage-report',
      'z-report-backfill',
    ]);
  });

  it('verteilt die stündlichen Jobs über die Stunde statt alle auf Minute 0', () => {
    // Alle gleichzeitig hieße: fünf Jobs konkurrieren mit dem Kassenbetrieb
    // um dieselben Zeilen (Sitzungen, Offline-Queue).
    const hourlyMinutes = jobs
      .filter((j) => /^\d+ \* \* \* \*$/.test(j.schedule))
      .map((j) => j.schedule.split(' ')[0]);
    expect(new Set(hourlyMinutes).size).toBe(hourlyMinutes.length);
    expect(hourlyMinutes).not.toContain('0');
  });

  it('plant in Europe/Berlin — „täglich 6 Uhr" meint Ortszeit des Wirts', () => {
    expect(CRON_TIMEZONE).toBe('Europe/Berlin');
    const daily = jobs.filter((j) => /^\d+ \d+ \* \* \*$/.test(j.schedule));
    expect(daily.length).toBeGreaterThan(0);
  });

  it('findet Jobs über findJob und liefert bei Unbekanntem undefined', () => {
    expect(findJob('trial-warnings')?.name).toBe('trial-warnings');
    expect(findJob('gibt-es-nicht')).toBeUndefined();
  });
});

describe('startCron / stopCron', () => {
  const previous = process.env['CRON_ENABLED'];

  afterEach(async () => {
    await stopCron();
    if (previous === undefined) delete process.env['CRON_ENABLED'];
    else process.env['CRON_ENABLED'] = previous;
  });

  it('registriert jeden Job genau einmal und meldet ihn zurück', async () => {
    delete process.env['CRON_ENABLED'];
    startCron();
    expect(scheduledJobNames()).toEqual(jobs.map((j) => j.name));

    // Zweiter Aufruf darf keine doppelten Timer anlegen (sonst liefe jeder Job zweimal).
    startCron();
    expect(scheduledJobNames()).toHaveLength(jobs.length);
  });

  it('legt bei CRON_ENABLED=false gar keine Timer an (zweite Instanz bleibt stumm)', () => {
    process.env['CRON_ENABLED'] = 'false';
    startCron();
    expect(scheduledJobNames()).toEqual([]);
  });

  it('stopCron räumt vollständig auf — ein Neustart im selben Prozess ist sauber', async () => {
    delete process.env['CRON_ENABLED'];
    startCron();
    await stopCron();
    expect(scheduledJobNames()).toEqual([]);
    startCron();
    expect(scheduledJobNames()).toHaveLength(jobs.length);
  });
});

describe('runJob', () => {
  it('gibt das Ergebnis des Jobs zurück', async () => {
    const result = await runJob({
      name: 'test-ok', schedule: '* * * * *', description: 'Test',
      run: async () => ({ done: 1 }),
    });
    expect(result).toEqual({ done: 1 });
  });

  it('schluckt Fehler, statt den Prozess mitzureißen', async () => {
    // index.ts fährt bei unhandledRejection herunter — ein gescheiterter
    // Warnmail-Job darf nicht die Kasse abschalten.
    const run = vi.fn(async () => { throw new Error('DB weg'); });
    await expect(
      runJob({ name: 'test-fail', schedule: '* * * * *', description: 'Test', run })
    ).resolves.toBeNull();
    expect(run).toHaveBeenCalledOnce();
  });
});

// scripts/run-job.ts
// Führt genau einen Cron-Job von Hand aus — ohne zu warten, bis der Zeitplan feuert.
//
//   npm run job -- --list
//   npm run job -- z-report-backfill
//
// Zweck: Betrieb (docs/betrieb.md). Nach einem Vorfall will man den Nachtrag
// sofort laufen lassen und nicht bis zur nächsten vollen Stunde warten. Jeder
// Job ist idempotent — ein manueller Lauf neben dem Zeitplan ist ungefährlich.

import dotenv from 'dotenv';
dotenv.config();

import { db, auditDb, readonlyDb } from '../db/index.js';
import { jobs, findJob } from '../jobs/index.js';
import { runJob } from '../cron.js';

function printJobs(): void {
  console.log('Verfügbare Jobs:');
  for (const job of jobs) {
    console.log(`  ${job.name.padEnd(22)} ${job.schedule.padEnd(12)} ${job.description}`);
  }
}

async function main(): Promise<void> {
  const name = process.argv[2];

  if (!name || name === '--list' || name === '-l') {
    printJobs();
    return;
  }

  const job = findJob(name);
  if (!job) {
    console.error(`✗ Unbekannter Job: ${name}\n`);
    printJobs();
    process.exitCode = 1;
    return;
  }

  console.log(`→ ${job.name}: ${job.description}`);
  const result = await runJob(job);
  if (result === null) {
    console.error('✗ Job fehlgeschlagen — Details im Log/Sentry.');
    process.exitCode = 1;
    return;
  }
  console.log(`✓ ${job.name}:`, result);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await Promise.allSettled([db.end(), auditDb.end(), readonlyDb.end()]);
  });

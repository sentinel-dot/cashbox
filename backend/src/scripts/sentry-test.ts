// scripts/sentry-test.ts
// Schickt genau ein Test-Event an Sentry und wartet, bis es raus ist.
//
// Zweck: nach dem Einrichten eines DSN (lokal wie auf Prod, S20) einmal
// verifizieren, dass die Kette wirklich bis ins Dashboard durchläuft — ein
// stiller Sentry ist schlimmer als kein Sentry, weil man sich auf ihn verlässt.
//
//   npm run sentry:test
//
// Der Fehler taucht im Dashboard als "S03 Test-Event" auf und kann dort
// anschließend als resolved/ignored weggeklickt werden.

import { captureException, flushSentry, sentryEnabled } from '../sentry.js';

async function main() {
  if (!sentryEnabled) {
    console.error('✗ SENTRY_DSN ist nicht gesetzt — es wird nichts gesendet.');
    console.error('  DSN in backend/.env eintragen (Sentry: Settings → Projects → Client Keys).');
    process.exit(1);
  }

  const dsn  = process.env['SENTRY_DSN'] ?? '';
  const host = dsn.match(/@([^/]+)\//)?.[1] ?? 'unbekannt';
  console.log(`→ Sende Test-Event an ${host} (environment: ${process.env['NODE_ENV'] ?? 'development'})`);

  captureException(new Error('S03 Test-Event — Sentry-Verdrahtung verifiziert'), {
    source: 'sentry:test',
    method: 'CLI',
    url:    'src/scripts/sentry-test.ts',
  });

  const ok = await flushSentry(10_000).then(() => true).catch(() => false);
  if (!ok) {
    console.error('✗ Flush fehlgeschlagen — Netzwerk/DSN prüfen.');
    process.exit(1);
  }

  console.log('✓ Event abgeschickt. Im Sentry-Dashboard unter "Issues" sollte jetzt');
  console.log('  "S03 Test-Event — Sentry-Verdrahtung verifiziert" stehen (ggf. 10–30 s warten).');
}

void main();

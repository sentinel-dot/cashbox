import { describe, it, expect } from 'vitest';
import { sentryEnabled } from '../../sentry.js';

// REQ-OPS-005 — Testläufe dürfen nichts ans Error-Monitoring melden.
//
// Regression zu OFFEN.md T10: `sentry.ts` rief `dotenv.config()` ohne Pfad und
// lud damit immer die Entwickler-`.env` — auch unter NODE_ENV=test. Wo lokal ein
// echter DSN steht, ging damit jeder Testfehler ins Produktionsprojekt. Dieser
// Test schlägt fehl, sobald der Pfad-Switch wieder verschwindet ODER jemand einen
// DSN in `.env.test` einträgt.
describe('Sentry-Konfiguration im Testlauf', () => {
  it('läuft unter NODE_ENV=test', () => {
    expect(process.env['NODE_ENV']).toBe('test');
  });

  it('ist deaktiviert — kein Event verlässt den Testlauf', () => {
    expect(sentryEnabled).toBe(false);
  });

  it('lädt keinen DSN aus der Entwickler-.env', () => {
    expect(process.env['SENTRY_DSN'] ?? '').toBe('');
  });
});

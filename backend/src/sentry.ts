// sentry.ts
// cashbox — Error-Monitoring (OFFEN.md S1)
//
// Muss der ERSTE Import in index.ts bleiben: Sentry instrumentiert http/express
// beim Laden, nicht beim Aufruf. Deshalb lädt diese Datei ihre eigene .env —
// dotenv.config() in index.ts liefe zu spät (dasselbe Muster wie db/index.ts).
//
// Ohne SENTRY_DSN bleibt Sentry komplett aus. Sentry.captureException ist dann
// ein No-Op, d.h. Tests und lokale Entwicklung laufen unverändert weiter, ohne
// dass irgendwo ein `if (sentryEnabled)` nötig wäre.
//
// DSGVO: Es werden bewusst KEINE Request-Bodies, Header oder Cookies gesendet
// (sendDefaultPii: false + kein Express-Request-Handler). An Sentry geht nur,
// was captureException() unten explizit als Tag mitgibt: URL, Methode, tenant_id.
// Keine Namen, keine Bons, keine Beträge — das ist für die AVV mit Sentry
// relevant (N8) und muss so bleiben.

import dotenv from 'dotenv';
// Denselben Pfad-Switch wie db/index.ts: ohne ihn lädt auch der Testlauf die
// Entwickler-.env samt echtem DSN — und meldet Testfehler ans Produktionsprojekt
// (genau das Dashboard, auf dem die Alert-Regel sitzt). OFFEN.md T10.
dotenv.config({ path: process.env['NODE_ENV'] === 'test' ? '.env.test' : '.env' });

import * as Sentry from '@sentry/node';
import { logger } from './logger.js';

const dsn = process.env['SENTRY_DSN'];

export const sentryEnabled = Boolean(dsn);

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env['NODE_ENV'] ?? 'development',
    // Nur Fehler, kein Performance-Tracing — Tracing würde jede Zahlung als
    // Transaktion an Sentry schicken; dafür gibt es Pino-Logs.
    tracesSampleRate: 0,
    // Keine personenbezogenen Daten (IP, Header, Body) automatisch anhängen.
    sendDefaultPii: false,
  });
  logger.info({ environment: process.env['NODE_ENV'] ?? 'development' }, 'Sentry aktiv');
} else {
  logger.info('Sentry deaktiviert (kein SENTRY_DSN gesetzt)');
}

/** Kontext, der an Sentry gehen darf — bewusst frei von Kunden-/Finanzdaten. */
export interface ErrorContext {
  url?:    string | undefined;
  method?: string | undefined;
  /** tenant_id ist je nach Aufrufer number oder string — Tags sind immer Strings. */
  tenant?: string | number | undefined;
  source?: string | undefined;
}

/**
 * Meldet einen Fehler an Sentry. No-Op wenn kein DSN konfiguriert ist.
 * tenant kommt aus dem JWT (req.auth), nie aus Body/Params — wie überall sonst.
 */
export function captureException(err: unknown, ctx: ErrorContext = {}): void {
  if (!sentryEnabled) return;

  Sentry.captureException(err, {
    tags: {
      ...(ctx.tenant !== undefined && { tenant: String(ctx.tenant) }),
      ...(ctx.method && { method: ctx.method }),
      ...(ctx.source && { source: ctx.source }),
    },
    ...(ctx.url && { extra: { url: ctx.url } }),
  });
}

/**
 * Wartet, bis gepufferte Events raus sind — beim Shutdown aufrufen, sonst geht
 * genau der Fehler verloren, der den Prozess beendet hat.
 */
export async function flushSentry(timeoutMs = 2000): Promise<void> {
  if (!sentryEnabled) return;
  try {
    await Sentry.flush(timeoutMs);
  } catch (err) {
    logger.warn({ err }, 'Sentry-Flush fehlgeschlagen');
  }
}

export default Sentry;

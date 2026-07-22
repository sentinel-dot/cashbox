// logger.ts
// cashbox — Strukturiertes Logging via Pino
// Production: JSON-Logs (für Log-Aggregation)
// Development: Pretty-Print im Terminal

import pino from 'pino';

const isDev = process.env['NODE_ENV'] !== 'production';

export const logger = pino({
  level: process.env['LOG_LEVEL'] ?? 'info',
  ...(isDev && {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'HH:MM:ss',
        ignore: 'pid,hostname',
        messageFormat: '{msg}',
      },
    },
  }),
});

/**
 * S08: Der Passwort-Reset-Link trägt seinen Token in der Query. Ein
 * Zugangsschlüssel hat in Logfiles nichts verloren — die werden aggregiert,
 * rotiert und weitergegeben. `pino-http` in app.ts loggt jede URL, deshalb wird
 * der Query-Teil genau dieser Route vorher ersetzt.
 *
 * Bewusst eine Whitelist statt „alles, was nach Token aussieht": Sie ist
 * überprüfbar, und ein vergessener Fall fällt beim Lesen auf statt still
 * durchzurutschen. Neue Routen mit Geheimnis in der URL hier eintragen.
 */
const REDACTED_QUERY_PATHS = new Set(['/auth/reset-password']);

export function redactUrl(url: string): string {
  const queryStart = url.indexOf('?');
  if (queryStart === -1) return url;
  const path = url.slice(0, queryStart);
  return REDACTED_QUERY_PATHS.has(path) ? `${path}?REDACTED` : url;
}

export default logger;

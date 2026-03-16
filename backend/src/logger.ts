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

export default logger;

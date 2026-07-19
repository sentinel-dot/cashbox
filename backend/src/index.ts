// index.ts
// cashbox — Prozess-Einstieg: Start, Signal-Handling, kontrolliertes Beenden.

// MUSS der erste Import bleiben: Sentry instrumentiert beim Laden (siehe sentry.ts).
import { captureException, flushSentry } from './sentry.js';

import dotenv from 'dotenv';
dotenv.config();

import app from './app.js';
import { db, auditDb, readonlyDb } from './db/index.js';
import { logger } from './logger.js';
import { createShutdown } from './shutdown.js';
import type { Server } from 'node:http';

const PORT = Number(process.env['PORT'] ?? 3000);

let server: Server | undefined;

const shutdown = createShutdown({
  closeServer: () =>
    new Promise<void>((resolve) => {
      if (!server) return resolve();
      // Ohne closeIdleConnections() wartet close() ewig auf Keep-Alive-Sockets,
      // auf denen gerade gar kein Request läuft (iPads halten die offen).
      server.closeIdleConnections();
      server.close(() => resolve());
    }),
  flushMonitoring: () => flushSentry(),
  closePools: async () => {
    // allSettled: ein kaputter Pool darf die anderen nicht am Schließen hindern.
    const results = await Promise.allSettled([db.end(), auditDb.end(), readonlyDb.end()]);
    const failed = results.filter((r) => r.status === 'rejected');
    if (failed.length > 0) {
      throw new AggregateError(
        failed.map((r) => (r as PromiseRejectedResult).reason),
        `${failed.length} DB-Pool(s) konnten nicht sauber geschlossen werden`,
      );
    }
  },
  exit: (code) => process.exit(code),
  log: logger,
});

// SIGTERM: Prozess-Manager (PM2/systemd) beim Deploy. SIGINT: Ctrl-C lokal.
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT',  () => void shutdown('SIGINT'));

// Node beendet sich bei unhandledRejection seit v15 ohnehin hart. Wir fangen es
// ab, um vorher zu loggen, an Sentry zu melden und laufende Requests zu Ende
// laufen zu lassen — ein halb geschriebener Bon ist teurer als ein paar Sekunden.
process.on('unhandledRejection', (reason) => {
  logger.error({ err: reason }, 'Unhandled Promise Rejection — fahre herunter');
  captureException(reason, { source: 'unhandledRejection' });
  void shutdown('unhandledRejection', 1);
});

// Nach uncaughtException ist der Prozess-Zustand unzuverlässig: weiterlaufen wäre
// gefährlicher als beenden (der Prozess-Manager startet neu).
process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'Uncaught Exception — fahre herunter');
  captureException(err, { source: 'uncaughtException' });
  void shutdown('uncaughtException', 1);
});

async function start() {
  // DB-Verbindung beim Start prüfen — lieber sofort scheitern als beim ersten Bon.
  try {
    await db.execute('SELECT 1');
    logger.info('Datenbankverbindung erfolgreich');
  } catch (err) {
    logger.fatal({ err }, 'Datenbankverbindung fehlgeschlagen');
    captureException(err, { source: 'startup' });
    await flushSentry();
    process.exit(1);
  }

  server = app.listen(PORT, () => {
    logger.info(
      { port: PORT, env: process.env['NODE_ENV'] ?? 'development' },
      `Server läuft auf Port ${PORT}`,
    );
  });
}

void start();

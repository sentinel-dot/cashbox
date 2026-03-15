import dotenv from 'dotenv';
dotenv.config();

import app from './app.js';
import { db } from './db/index.js';

const PORT = Number(process.env['PORT'] ?? 3000);

async function start() {
  // Verify DB connection on startup
  try {
    await db.execute('SELECT 1');
    console.log('✓ Datenbankverbindung erfolgreich');
  } catch (err) {
    console.error('✗ Datenbankverbindung fehlgeschlagen:', err);
    process.exit(1);
  }

  app.listen(PORT, () => {
    console.log(`✓ Server läuft auf Port ${PORT} (${process.env['NODE_ENV'] ?? 'development'})`);
  });
}

start();

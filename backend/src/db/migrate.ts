import mysql from 'mysql2/promise';
import path from 'path';
import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config({ path: process.env['DOTENV_CONFIG_PATH'] ?? '.env' });

async function getMigrationFiles(): Promise<string[]> {
  const dir = path.join(__dirname, 'migrations');
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.ts') || f.endsWith('.js'))
    .sort();
}

async function run() {
  const conn = await mysql.createConnection({
    host:     process.env['DB_HOST']     ?? 'localhost',
    port:     Number(process.env['DB_PORT'] ?? 3306),
    database: process.env['DB_NAME']     ?? 'cashbox',
    user:     process.env['DB_USER']     ?? '',
    password: process.env['DB_PASSWORD'] ?? '',
    timezone: '+00:00',
    multipleStatements: false,
  });

  // Migrations-Tracking-Tabelle anlegen
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      filename   VARCHAR(255) NOT NULL,
      applied_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_schema_migrations_filename (filename)
    ) ENGINE=InnoDB
  `);

  const [appliedRows] = await conn.execute<any[]>('SELECT filename FROM schema_migrations');
  const applied = new Set(appliedRows.map((r: any) => r.filename));

  const files = await getMigrationFiles();
  let ran = 0;

  for (const file of files) {
    if (applied.has(file)) continue;

    console.log(`Applying migration: ${file}`);
    const mod = require(path.join(__dirname, 'migrations', file));

    await conn.beginTransaction();
    try {
      await mod.up(conn);
      await conn.execute('INSERT INTO schema_migrations (filename) VALUES (?)', [file]);
      await conn.commit();
      console.log(`  ✓ ${file}`);
      ran++;
    } catch (err) {
      await conn.rollback();
      console.error(`  ✗ ${file}:`, err);
      await conn.end();
      process.exit(1);
    }
  }

  if (ran === 0) {
    console.log('Keine neuen Migrationen.');
  } else {
    console.log(`${ran} Migration(en) erfolgreich angewendet.`);
  }

  await conn.end();
}

run();

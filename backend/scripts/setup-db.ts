/**
 * scripts/setup-db.ts
 *
 * Legt Datenbank, User und Grants idempotent an — nur für development/test.
 * In production werden User manuell vom DBA angelegt.
 *
 * Benötigt Admin-Credentials mit CREATE USER + GRANT OPTION:
 *   DB_ADMIN_USER=root  (oder ein MariaDB-Admin-User)
 *   DB_ADMIN_PASSWORD=...
 *
 * Usage:
 *   npm run db:setup           # development (.env)
 *   npm run db:setup:test      # test (.env.test)
 *
 * Was das Script tut:
 *   1. Verbindet als Admin
 *   2. CREATE DATABASE IF NOT EXISTS
 *   3. CREATE USER IF NOT EXISTS für app_user, audit_insert_user, app_readonly
 *   4. Grants vergeben
 *   5. FLUSH PRIVILEGES
 *   6. Migrations ausführen (npm run migrate / migrate:test)
 */

import mysql from 'mysql2/promise';
import { execSync } from 'child_process';
import path from 'path';
import dotenv from 'dotenv';

// ─── Env laden ────────────────────────────────────────────────────────────────

const envFile = process.env['DOTENV_CONFIG_PATH'] ?? '.env';
dotenv.config({ path: path.resolve(process.cwd(), envFile) });

const NODE_ENV = process.env['NODE_ENV'] ?? 'development';

if (NODE_ENV === 'production') {
  console.error('❌  setup-db darf nicht in production laufen. DB-User manuell via DBA anlegen.');
  process.exit(1);
}

// ─── Konfiguration lesen ──────────────────────────────────────────────────────

function require_env(key: string): string {
  const val = process.env[key];
  if (!val) {
    console.error(`❌  Env-Variable ${key} fehlt. In ${envFile} setzen.`);
    process.exit(1);
  }
  return val;
}

const DB_HOST     = process.env['DB_HOST']     ?? 'localhost';
const DB_PORT     = Number(process.env['DB_PORT'] ?? 3306);
const DB_NAME     = require_env('DB_NAME');

// App-User (SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER)
const DB_USER     = require_env('DB_USER');
const DB_PASSWORD = require_env('DB_PASSWORD');

// Audit-User (INSERT only — für audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals)
const DB_AUDIT_USER     = require_env('DB_AUDIT_USER');
const DB_AUDIT_PASSWORD = require_env('DB_AUDIT_PASSWORD');

// Readonly-User (SELECT only — für Reports, Admin-Panel)
const DB_READONLY_USER     = require_env('DB_READONLY_USER');
const DB_READONLY_PASSWORD = require_env('DB_READONLY_PASSWORD');

// Admin-User (braucht CREATE USER + GRANT OPTION)
// Varianten:
//   Passwort-Auth:    DB_ADMIN_USER=root, DB_ADMIN_PASSWORD=secret
//   Unix-Socket-Auth: DB_ADMIN_USER=root, DB_ADMIN_PASSWORD= (leer lassen)
//                     → Verbindung über socketPath statt TCP
const DB_ADMIN_USER     = process.env['DB_ADMIN_USER']     ?? 'root';
const DB_ADMIN_PASSWORD = process.env['DB_ADMIN_PASSWORD'] ?? '';
const DB_ADMIN_SOCKET   = process.env['DB_ADMIN_SOCKET']   ?? '/var/run/mysqld/mysqld.sock';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function run(conn: mysql.Connection, sql: string, label?: string): Promise<void> {
  try {
    await conn.execute(sql);
    if (label) console.log(`  ✓ ${label}`);
  } catch (err: any) {
    // "already exists"-Fehler ignorieren — Script ist idempotent
    if (err.code === 'ER_CANNOT_USER' || err.errno === 1396) {
      if (label) console.log(`  ~ ${label} (bereits vorhanden)`);
      return;
    }
    throw err;
  }
}

// ─── Hauptlogik ───────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log(`\n🗄️  cashbox DB-Setup (${NODE_ENV}, DB: ${DB_NAME})\n`);

  // Admin-Verbindung (ohne Datenbank — CREATE DATABASE muss ohne aktive DB laufen)
  // Bei leerem Passwort: Unix-Socket-Auth versuchen (für MariaDB mit auth_socket-Plugin)
  const useSocket = !DB_ADMIN_PASSWORD && DB_ADMIN_USER === 'root';
  const connConfig: mysql.ConnectionOptions = useSocket
    ? { socketPath: DB_ADMIN_SOCKET, user: DB_ADMIN_USER, timezone: '+00:00', multipleStatements: false }
    : { host: DB_HOST, port: DB_PORT, user: DB_ADMIN_USER, password: DB_ADMIN_PASSWORD, timezone: '+00:00', multipleStatements: false };

  const connDesc = useSocket
    ? `${DB_ADMIN_USER} via ${DB_ADMIN_SOCKET}`
    : `${DB_ADMIN_USER}@${DB_HOST}:${DB_PORT}`;

  const conn = await mysql.createConnection(connConfig).catch((err) => {
    console.error(`❌  Admin-Verbindung fehlgeschlagen (${connDesc})`);
    console.error(`    Fehler: ${err.message}`);
    console.error(`    Optionen:`);
    console.error(`      1. DB_ADMIN_PASSWORD=<passwort> in ${envFile} setzen`);
    console.error(`      2. Script mit sudo ausführen: sudo npm run db:setup`);
    console.error(`      3. DB_ADMIN_SOCKET=<pfad> anpassen (Standard: /var/run/mysqld/mysqld.sock)`);
    process.exit(1);
  });

  try {
    // 1. Datenbank anlegen
    await run(conn,
      `CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
       CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
      `Datenbank '${DB_NAME}'`
    );

    // 2. User anlegen (idempotent via IF NOT EXISTS)
    await run(conn,
      `CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}'`,
      `User '${DB_USER}'`
    );
    await run(conn,
      `CREATE USER IF NOT EXISTS '${DB_AUDIT_USER}'@'localhost' IDENTIFIED BY '${DB_AUDIT_PASSWORD}'`,
      `User '${DB_AUDIT_USER}'`
    );
    await run(conn,
      `CREATE USER IF NOT EXISTS '${DB_READONLY_USER}'@'localhost' IDENTIFIED BY '${DB_READONLY_PASSWORD}'`,
      `User '${DB_READONLY_USER}'`
    );

    // 3. Grants
    //
    // app_user: vollständige App-Rechte + ALTER/CREATE für Migrations
    await run(conn,
      `GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'`,
      `Grants für '${DB_USER}'`
    );

    // audit_insert_user: nur INSERT (GoBD: append-only auf Finanztabellen)
    // Hinweis: In Production engere Grants pro Tabelle setzen (nach Migration):
    //   GRANT INSERT ON cashbox.audit_log TO ...
    //   GRANT INSERT ON cashbox.z_reports TO ...
    //   GRANT INSERT ON cashbox.product_price_history TO ...
    //   GRANT INSERT ON cashbox.order_item_modifiers TO ...
    //   GRANT INSERT ON cashbox.order_item_removals TO ...
    await run(conn,
      `GRANT INSERT ON \`${DB_NAME}\`.* TO '${DB_AUDIT_USER}'@'localhost'`,
      `Grants für '${DB_AUDIT_USER}' (INSERT only)`
    );

    // app_readonly: nur SELECT
    await run(conn,
      `GRANT SELECT ON \`${DB_NAME}\`.* TO '${DB_READONLY_USER}'@'localhost'`,
      `Grants für '${DB_READONLY_USER}' (SELECT only)`
    );

    await conn.execute('FLUSH PRIVILEGES');
    console.log('  ✓ FLUSH PRIVILEGES');

  } finally {
    await conn.end();
  }

  // 4. Migrations ausführen
  console.log('\n📦  Migrations ausführen...');
  const migrateCmd = NODE_ENV === 'test'
    ? 'npm run migrate:test'
    : 'npm run migrate';

  try {
    execSync(migrateCmd, { stdio: 'inherit', cwd: process.cwd() });
  } catch {
    console.error('❌  Migration fehlgeschlagen. DB-Zustand prüfen.');
    process.exit(1);
  }

  console.log(`\n✅  Setup abgeschlossen. Nächster Schritt: npm run dev\n`);
}

main().catch((err) => {
  console.error('❌  Unerwarteter Fehler:', err.message);
  process.exit(1);
});

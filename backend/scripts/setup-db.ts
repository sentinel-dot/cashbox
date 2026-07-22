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
 * Optional:
 *   DB_USER_HOST=%      Host-Teil der angelegten User/Grants (Default: localhost).
 *                       In CI nötig: dort läuft MariaDB als Service-Container, die
 *                       Verbindung kommt aus dem Docker-Netz an — nicht von localhost.
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

// Audit-User (INSERT only — und nur auf den append-only-Tabellen unten)
const DB_AUDIT_USER     = require_env('DB_AUDIT_USER');
const DB_AUDIT_PASSWORD = require_env('DB_AUDIT_PASSWORD');

// Die einzigen Tabellen, in die audit_insert_user schreiben darf (GoBD: append-only).
// Muss deckungsgleich bleiben mit CLAUDE.md "DB-Berechtigungen" und den auditDb-
// Aufrufern (services/audit.ts, priceHistory.ts, orderItemModifiers.ts,
// email/queue.ts, sessionsController, jobs/zReportBackfill).
// Regressionsschutz: integration/db-grants.test.ts
const AUDIT_INSERT_TABLES = [
  'audit_log',
  'z_reports',
  'product_price_history',
  'order_item_modifiers',
  'order_item_removals',
  'email_log',
];

// Readonly-User (SELECT only — für Reports, Admin-Panel)
const DB_READONLY_USER     = require_env('DB_READONLY_USER');
const DB_READONLY_PASSWORD = require_env('DB_READONLY_PASSWORD');

// Admin-User (braucht CREATE USER + GRANT OPTION)
// Varianten:
//   Passwort-Auth:    DB_ADMIN_USER=root, DB_ADMIN_PASSWORD=secret
//   Unix-Socket-Auth: DB_ADMIN_PASSWORD= (leer lassen), beliebiger DB_ADMIN_USER
//                     → Verbindung über socketPath statt TCP (macOS/Homebrew:
//                       DB_ADMIN_USER=<macOS-User> DB_ADMIN_SOCKET=/tmp/mysql.sock)
const DB_ADMIN_USER     = process.env['DB_ADMIN_USER']     ?? 'root';
const DB_ADMIN_PASSWORD = process.env['DB_ADMIN_PASSWORD'] ?? '';
const DB_ADMIN_SOCKET   = process.env['DB_ADMIN_SOCKET']   ?? '/var/run/mysqld/mysqld.sock';

// Host-Teil der angelegten User und ihrer Grants. Lokal 'localhost'; in CI '%',
// weil Verbindungen dort aus dem Docker-Netz des MariaDB-Service-Containers
// kommen und ein 'localhost'-Grant nicht greifen würde.
const DB_USER_HOST = process.env['DB_USER_HOST'] ?? 'localhost';

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
  const useSocket = !DB_ADMIN_PASSWORD;
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
      `CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_USER_HOST}' IDENTIFIED BY '${DB_PASSWORD}'`,
      `User '${DB_USER}'`
    );
    await run(conn,
      `CREATE USER IF NOT EXISTS '${DB_AUDIT_USER}'@'${DB_USER_HOST}' IDENTIFIED BY '${DB_AUDIT_PASSWORD}'`,
      `User '${DB_AUDIT_USER}'`
    );
    await run(conn,
      `CREATE USER IF NOT EXISTS '${DB_READONLY_USER}'@'${DB_USER_HOST}' IDENTIFIED BY '${DB_READONLY_PASSWORD}'`,
      `User '${DB_READONLY_USER}'`
    );

    // 3. Grants
    //
    // app_user: App-Rechte + ALTER/CREATE/INDEX für Migrations — OHNE pauschales
    // DELETE: die GoBD-Tabellen (orders, order_items, receipts, payments,
    // cancellations, audit_log, z_reports, product_price_history,
    // order_item_modifiers, order_item_removals, cash_register_sessions,
    // cash_movements) sind append-only; die DB muss das erzwingen, nicht nur
    // der Code. DELETE gibt es nur tabellen-scoped auf operativen Tabellen
    // (Seed-Rollback V005) — bzw. in der Test-DB pauschal (testHelpers wischen
    // zwischen Testläufen alle Tabellen).
    await run(conn,
      `GRANT SELECT, INSERT, UPDATE, CREATE, ALTER, INDEX ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_USER_HOST}'`,
      `Grants für '${DB_USER}'`
    );
    if (NODE_ENV === 'test') {
      await run(conn,
        `GRANT DELETE ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_USER_HOST}'`,
        `Grants für '${DB_USER}' (DELETE — nur Test-DB)`
      );
    } else {
      // Früher vergebenes pauschales DELETE entziehen (Grants sind additiv —
      // ohne REVOKE bliebe es auf bestehenden Dev-DBs bestehen)
      try {
        await conn.execute(`REVOKE DELETE ON \`${DB_NAME}\`.* FROM '${DB_USER}'@'${DB_USER_HOST}'`);
        console.log(`  ✓ Pauschales DELETE für '${DB_USER}' entzogen`);
      } catch {
        // kein bestehender DELETE-Grant — nichts zu entziehen
      }
      // Nicht-Finanztabellen, die der Seed-Rollback (V005 down) leeren darf.
      // Tabellen-Grants funktionieren auch bevor die Tabelle existiert.
      const DELETABLE_TABLES = [
        'tenants', 'users', 'devices', 'products', 'product_categories',
        'product_modifier_groups', 'product_modifier_options',
        'tables', 'zones', 'receipt_sequences',
      ];
      for (const table of DELETABLE_TABLES) {
        await run(conn,
          `GRANT DELETE ON \`${DB_NAME}\`.\`${table}\` TO '${DB_USER}'@'${DB_USER_HOST}'`,
        );
      }
      console.log(`  ✓ Grants für '${DB_USER}' (DELETE nur auf ${DELETABLE_TABLES.length} Nicht-Finanztabellen)`);
    }

    // audit_insert_user: INSERT, und zwar NUR auf den append-only-Tabellen
    // (GoBD). Ein pauschales INSERT auf *.* hieße: wer diese Zugangsdaten
    // erbeutet, schreibt auch orders, payments oder users — der Sinn des
    // zweiten Users ist aber, dass genau das nicht geht (Audit #1, A6).
    // Beim Erweitern: Tabelle hier eintragen UND in CLAUDE.md
    // "DB-Berechtigungen" nachziehen, sonst scheitert der INSERT zur Laufzeit.
    // Grants auf noch nicht existierende Tabellen sind zulässig — das Script
    // läuft vor den Migrations.
    for (const table of AUDIT_INSERT_TABLES) {
      await run(conn,
        `GRANT INSERT ON \`${DB_NAME}\`.\`${table}\` TO '${DB_AUDIT_USER}'@'${DB_USER_HOST}'`,
      );
    }
    // Früher vergebenes pauschales INSERT entziehen (Grants sind additiv —
    // ohne REVOKE bliebe es auf bestehenden Dev-/Prod-DBs stehen)
    try {
      await conn.execute(`REVOKE INSERT ON \`${DB_NAME}\`.* FROM '${DB_AUDIT_USER}'@'${DB_USER_HOST}'`);
      console.log(`  ✓ Pauschales INSERT für '${DB_AUDIT_USER}' entzogen`);
    } catch {
      // kein bestehender datenbankweiter INSERT-Grant — nichts zu entziehen
    }
    console.log(`  ✓ Grants für '${DB_AUDIT_USER}' (INSERT nur auf ${AUDIT_INSERT_TABLES.length} Audit-Tabellen)`);

    // app_readonly: nur SELECT
    await run(conn,
      `GRANT SELECT ON \`${DB_NAME}\`.* TO '${DB_READONLY_USER}'@'${DB_USER_HOST}'`,
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

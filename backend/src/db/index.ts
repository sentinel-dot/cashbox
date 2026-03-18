import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

dotenv.config({ path: process.env['NODE_ENV'] === 'test' ? '.env.test' : '.env' });

function createPool(user: string, password: string) {
  const pool = mysql.createPool({
    host: process.env['DB_HOST'] ?? 'localhost',
    port: Number(process.env['DB_PORT'] ?? 3306),
    database: process.env['DB_NAME'] ?? 'cashbox',
    user,
    password,
    waitForConnections: true,
    connectionLimit: 10,
    timezone: '+00:00',
  });

  // mysql2's `timezone` option beeinflusst nur das Client-Side-Parsing, NICHT
  // das Server-Side NOW()/CURRENT_TIMESTAMP. Ohne diesen Hook speichert MariaDB
  // DATETIME DEFAULT CURRENT_TIMESTAMP in der Systemzeit des Hosts (z.B. UTC-7),
  // während mysql2 es als UTC liest → falsche Zeitdifferenzen im Frontend.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (pool as any).pool.on('connection', (conn: any) => {
    conn.query("SET time_zone = '+00:00'");
  });

  return pool;
}

// Standard app pool: SELECT, INSERT, UPDATE on standard tables
export const db = createPool(
  process.env['DB_USER'] ?? '',
  process.env['DB_PASSWORD'] ?? ''
);

// Audit pool: INSERT-only on audit_log, z_reports, product_price_history, order_item_modifiers
export const auditDb = createPool(
  process.env['DB_AUDIT_USER'] ?? '',
  process.env['DB_AUDIT_PASSWORD'] ?? ''
);

// Readonly pool: SELECT-only (reports, admin panel)
export const readonlyDb = createPool(
  process.env['DB_READONLY_USER'] ?? '',
  process.env['DB_READONLY_PASSWORD'] ?? ''
);

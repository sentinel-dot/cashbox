import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

dotenv.config({ path: process.env['NODE_ENV'] === 'test' ? '.env.test' : '.env' });

function createPool(user: string, password: string) {
  return mysql.createPool({
    host: process.env['DB_HOST'] ?? 'localhost',
    port: Number(process.env['DB_PORT'] ?? 3306),
    database: process.env['DB_NAME'] ?? 'cashbox',
    user,
    password,
    waitForConnections: true,
    connectionLimit: 10,
    timezone: '+00:00',
  });
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

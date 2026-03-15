import { Connection } from 'mysql2/promise';

export async function up(db: Connection): Promise<void> {
  // 'trial' zum subscription_status-Enum hinzufügen und als Default setzen.
  // Neue Tenants starten immer mit 14 Tagen Trial (subscriptionMiddleware prüft via created_at).
  await db.execute(`
    ALTER TABLE tenants
    MODIFY subscription_status ENUM('trial','active','past_due','cancelled') NOT NULL DEFAULT 'trial'
  `);

  // Stripe-Events für Webhook-Idempotenz: Stripe kann Events mehrfach senden.
  // Diese Tabelle verhindert doppelte Verarbeitung über die Stripe-Event-ID (evt_...).
  await db.execute(`
    CREATE TABLE IF NOT EXISTS stripe_events (
      id           VARCHAR(255) NOT NULL,
      processed_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

export async function down(db: Connection): Promise<void> {
  await db.execute('DROP TABLE IF EXISTS stripe_events');

  await db.execute(`
    ALTER TABLE tenants
    MODIFY subscription_status ENUM('active','past_due','cancelled') NOT NULL DEFAULT 'active'
  `);
}

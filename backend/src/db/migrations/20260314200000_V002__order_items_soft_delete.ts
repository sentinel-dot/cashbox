import { Connection } from 'mysql2/promise';

export async function up(db: Connection): Promise<void> {
  // GoBD: order_items dürfen nie physisch gelöscht werden.
  // Entfernen einer Position vor Zahlung wird in order_item_removals dokumentiert.
  // Queries filtern über NOT EXISTS / LEFT JOIN statt is_active-Spalte.
  // Vorteil: explizite Dokumentation von wer, wann, warum entfernt hat.
  await db.execute(`
    CREATE TABLE IF NOT EXISTS order_item_removals (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      order_item_id       INT UNSIGNED  NOT NULL,
      removed_by_user_id  INT UNSIGNED  NOT NULL,
      reason              VARCHAR(500)  NULL,      -- GoBD: Begründung empfohlen (optional, da audit_log Pflicht)
      created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_oir_order_item FOREIGN KEY (order_item_id) REFERENCES order_items(id),
      CONSTRAINT fk_oir_user       FOREIGN KEY (removed_by_user_id) REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

export async function down(db: Connection): Promise<void> {
  await db.execute('DROP TABLE IF EXISTS order_item_removals');
}

import { Connection } from 'mysql2/promise';

// S17B (docs/s17-sortiment-starterpakete.md §6.1 + §8.2):
// - products.visual_key: semantischer Schlüssel (NULL = Textkachel; Whitelist
//   validiert der Server — die DB speichert nie SF-Symbol-Namen oder Asset-Pfade)
// - Preset-Herkunft (origin_*) auf Produkten und Kategorien + UNIQUE je Tenant:
//   Retry/Doppeltap/erneuter Import erzeugt für denselben stabilen Item-Key kein
//   Duplikat. MariaDB-UNIQUE ignoriert NULLs — manuell angelegte Zeilen (origin
//   komplett NULL) bleiben unberührt.
// - preset_imports: Idempotenz-Anker je (tenant, Idempotency-Key) nach dem
//   stripe_events-Muster (INSERT in TX, ER_DUP_ENTRY ⇒ Replay), plus operativer
//   Status für Crash-Übernahme (stale processing).
export async function up(db: Connection): Promise<void> {
  await db.execute(
    `ALTER TABLE products
       ADD COLUMN visual_key            VARCHAR(64)  NULL AFTER sort_order,
       ADD COLUMN origin_preset_id      VARCHAR(32)  NULL,
       ADD COLUMN origin_preset_version INT UNSIGNED NULL,
       ADD COLUMN origin_item_key       VARCHAR(64)  NULL,
       ADD UNIQUE KEY uq_products_origin (tenant_id, origin_preset_id, origin_item_key)`
  );

  await db.execute(
    `ALTER TABLE product_categories
       ADD COLUMN origin_preset_id      VARCHAR(32)  NULL,
       ADD COLUMN origin_preset_version INT UNSIGNED NULL,
       ADD COLUMN origin_category_key   VARCHAR(64)  NULL,
       ADD UNIQUE KEY uq_categories_origin (tenant_id, origin_preset_id, origin_category_key)`
  );

  await db.execute(
    `CREATE TABLE preset_imports (
       id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
       tenant_id            INT UNSIGNED NOT NULL,
       idempotency_key      CHAR(36)     NOT NULL,
       preset_id            VARCHAR(32)  NOT NULL,
       preset_version       INT UNSIGNED NOT NULL,
       tax_basis_version    VARCHAR(32)  NOT NULL,
       requested_by_user_id INT UNSIGNED NOT NULL,
       status               ENUM('processing','completed','failed') NOT NULL DEFAULT 'processing',
       result_json          JSON         NULL,
       created_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
       completed_at         DATETIME     NULL,
       UNIQUE KEY uq_preset_imports_idem (tenant_id, idempotency_key),
       CONSTRAINT fk_preset_imports_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
  );
}

export async function down(db: Connection): Promise<void> {
  await db.execute('DROP TABLE preset_imports');
  await db.execute(
    `ALTER TABLE product_categories
       DROP INDEX uq_categories_origin,
       DROP COLUMN origin_preset_id,
       DROP COLUMN origin_preset_version,
       DROP COLUMN origin_category_key`
  );
  await db.execute(
    `ALTER TABLE products
       DROP INDEX uq_products_origin,
       DROP COLUMN visual_key,
       DROP COLUMN origin_preset_id,
       DROP COLUMN origin_preset_version,
       DROP COLUMN origin_item_key`
  );
}

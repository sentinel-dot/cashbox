import { Connection } from 'mysql2/promise';

// S17A (OFFEN.md UX-S1): Produkte bekommen eine persistente Kassen-Reihenfolge.
// Backfill: pro (tenant, category) alphabetisch × 10 — die heute sichtbare
// Reihenfolge wird zum gespeicherten Startzustand, mit Lücken zum Einsortieren.
export async function up(db: Connection): Promise<void> {
  await db.execute(
    'ALTER TABLE products ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER category_id'
  );
  await db.execute(
    `UPDATE products p
     JOIN (
       SELECT id, ROW_NUMBER() OVER (
         PARTITION BY tenant_id, category_id ORDER BY name ASC, id ASC
       ) * 10 AS rn
       FROM products
     ) x ON x.id = p.id
     SET p.sort_order = x.rn, p.updated_at = p.updated_at`
  );
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE products DROP COLUMN sort_order');
}

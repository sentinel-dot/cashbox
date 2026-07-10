import { Connection } from 'mysql2/promise';

// GoBD-Backstop: Ein Bon darf nur EINMAL storniert werden. Ohne diesen Constraint
// können zwei parallele Storno-Requests (Doppel-Tap) beide durchkommen — der Umsatz
// würde doppelt negiert, und weil Storno-von-Storno korrekt blockiert ist, wäre das
// über die App nicht mehr korrigierbar. Der Controller prüft zusätzlich in der TX
// (FOR-UPDATE-Lock auf dem Original-Bon); der UNIQUE-Constraint ist die DB-Garantie.
export async function up(db: Connection): Promise<void> {
  await db.execute(
    'ALTER TABLE cancellations ADD CONSTRAINT uq_cancellations_original UNIQUE (original_receipt_id)'
  );
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE cancellations DROP INDEX uq_cancellations_original');
}

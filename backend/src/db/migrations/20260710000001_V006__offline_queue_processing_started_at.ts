import { Connection } from 'mysql2/promise';

export async function up(db: Connection): Promise<void> {
  // Zeitpunkt des Processing-Claims — Grundlage für den Stuck-Reset:
  // created_at ist dafür ungeeignet (alter Eintrag würde direkt nach dem
  // Claim wieder auf 'pending' zurückgesetzt → Doppelverarbeitung).
  await db.execute(`
    ALTER TABLE offline_queue
      ADD COLUMN processing_started_at DATETIME NULL AFTER synced_at
  `);
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE offline_queue DROP COLUMN processing_started_at');
}

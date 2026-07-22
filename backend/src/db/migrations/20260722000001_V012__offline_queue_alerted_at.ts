import { Connection } from 'mysql2/promise';

// S07 (OFFEN.md B2): Der stündliche Cron-Job alarmiert bei endgültig gescheiterten
// Offline-Queue-Einträgen (= ein Bon ohne TSE-Signatur, KassenSichV-relevant).
// Ohne Marker würde er jede Stunde erneut denselben Vorfall melden, bis jemand
// die Zeile anfasst — Alarmmüdigkeit ist die sicherste Art, echte Ausfälle zu
// übersehen. `alerted_at` ist ein operatives Zustandsfeld (UPDATE erlaubt,
// offline_queue ist keine Finanztabelle).
export async function up(db: Connection): Promise<void> {
  await db.execute(
    `ALTER TABLE offline_queue
     ADD COLUMN alerted_at DATETIME NULL
       COMMENT 'Wann über diesen failed-Eintrag alarmiert wurde (Cron-Dedup, S07)'`
  );
  // Der Alert-Job soll nach dem Deploy nicht die gesamte Historie melden.
  await db.execute(
    `UPDATE offline_queue SET alerted_at = NOW() WHERE status = 'failed'`
  );

  // Backstop für den Z-Bericht-Nachtrag (A9): Genau EIN Z-Bericht pro Session.
  // closeSession kann eine Session nur einmal schließen, aber der Nachtrags-Cron
  // ist ein zweiter Schreiber — und z_reports ist INSERT-only, ein doppelter
  // Bericht wäre nicht mehr korrigierbar. Wie V008 bei cancellations: die
  // Eindeutigkeit gehört in die DB, nicht nur in den Controller.
  await db.execute(
    'ALTER TABLE z_reports ADD CONSTRAINT uq_z_reports_session UNIQUE (session_id)'
  );
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE z_reports DROP INDEX uq_z_reports_session');
  await db.execute('ALTER TABLE offline_queue DROP COLUMN alerted_at');
}

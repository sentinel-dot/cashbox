import { db } from '../db/index.js';

/**
 * Aktuelles Datum (YYYY-MM-DD) in der Zeitzone, in der die Berichte bucketen
 * (`REPORT_TZ` in reportsController: Europe/Berlin).
 *
 * NICHT durch `new Date().toISOString().slice(0, 10)` ersetzen: das liefert das
 * UTC-Datum. Zwischen 00:00 und 02:00 Berliner Zeit (22:00–24:00 UTC) liegt das
 * Berliner Datum einen Tag vor dem UTC-Datum — ein Test, der Bons „jetzt" anlegt
 * und dann den UTC-Tag abfragt, bekommt dann korrekterweise 0 zurück und wird rot,
 * obwohl die Berichtslogik stimmt. Für eine Bar, die über Mitternacht offen hat,
 * ist die Berliner Bucketierung genau das gewünschte Verhalten.
 */
export function berlinDate(d: Date = new Date()): string {
  // en-CA formatiert als YYYY-MM-DD
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Berlin',
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

/** Berliner Datum vor `n` Tagen (YYYY-MM-DD). */
export function berlinDateDaysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return berlinDate(d);
}

/**
 * Löscht alle Test-Daten in FK-sicherer Reihenfolge (Kinder vor Eltern).
 * Kein SET foreign_key_checks — damit werden keine Pool-Connections kontaminiert.
 */
export async function cleanTestDB(): Promise<void> {
  // Reihenfolge: abhängige Tabellen zuerst, tenants zuletzt
  const tables = [
    'stripe_events', 'preset_imports',
    'subscription_events', 'tse_outages', 'audit_log', 'offline_queue',
    'email_log', 'email_queue',
    'cancellations', 'payment_splits', 'payments', 'receipts',
    'order_item_removals', 'order_item_modifiers', 'order_items', 'orders', 'cash_movements',
    'z_reports', 'cash_register_sessions', 'receipt_sequences',
    'tables', 'zones', 'product_modifier_options', 'product_modifier_groups',
    'product_price_history', 'products', 'product_categories',
    'password_reset_tokens',
    'devices', 'users', 'tenants',
  ];
  for (const table of tables) {
    await db.execute(`DELETE FROM \`${table}\``);
  }
}

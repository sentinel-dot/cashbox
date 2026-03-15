import { db } from '../db/index.js';

/**
 * Löscht alle Test-Daten in FK-sicherer Reihenfolge (Kinder vor Eltern).
 * Kein SET foreign_key_checks — damit werden keine Pool-Connections kontaminiert.
 */
export async function cleanTestDB(): Promise<void> {
  // Reihenfolge: abhängige Tabellen zuerst, tenants zuletzt
  const tables = [
    'stripe_events',
    'subscription_events', 'tse_outages', 'audit_log', 'offline_queue',
    'cancellations', 'payment_splits', 'payments', 'receipts',
    'order_item_removals', 'order_item_modifiers', 'order_items', 'orders', 'cash_movements',
    'z_reports', 'cash_register_sessions', 'receipt_sequences',
    'tables', 'zones', 'product_modifier_options', 'product_modifier_groups',
    'product_price_history', 'products', 'product_categories',
    'devices', 'users', 'tenants',
  ];
  for (const table of tables) {
    await db.execute(`DELETE FROM \`${table}\``);
  }
}

import { Connection } from 'mysql2/promise';

// Indizes für die heißesten Query-Pfade:
// - receipts(tenant_id, created_at): Berichte + Bon-Liste (Datumsfilter)
// - orders(session_id, status):      listOrders, closeSession-Check, Z-Bericht
// - offline_queue(tenant_id, status): Sync-Batch + Status-Zählung
export async function up(db: Connection): Promise<void> {
  await db.execute('CREATE INDEX idx_receipts_tenant_created ON receipts (tenant_id, created_at)');
  await db.execute('CREATE INDEX idx_orders_session_status   ON orders (session_id, status)');
  await db.execute('CREATE INDEX idx_offline_queue_tenant_status ON offline_queue (tenant_id, status)');
}

export async function down(db: Connection): Promise<void> {
  await db.execute('DROP INDEX idx_receipts_tenant_created ON receipts');
  await db.execute('DROP INDEX idx_orders_session_status ON orders');
  await db.execute('DROP INDEX idx_offline_queue_tenant_status ON offline_queue');
}

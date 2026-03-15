import type { PoolConnection } from 'mysql2/promise';

/**
 * Holt die nächste Bon-Nummer für einen Tenant atomar via SELECT … FOR UPDATE.
 * Muss innerhalb einer offenen DB-Transaktion aufgerufen werden.
 *
 * GoBD: Bon-Nummern dürfen keine Lücken haben. AUTO_INCREMENT ist verboten,
 * weil Rollbacks unsichtbare Lücken erzeugen würden.
 */
export async function nextReceiptNumber(tenantId: number, conn: PoolConnection): Promise<number> {
  const [rows] = await conn.execute<any[]>(
    'SELECT last_number FROM receipt_sequences WHERE tenant_id = ? FOR UPDATE',
    [tenantId]
  );
  if (rows.length === 0) {
    throw new Error(`receipt_sequences-Eintrag für tenant_id=${tenantId} fehlt.`);
  }
  const newNumber = (rows[0].last_number as number) + 1;
  await conn.execute(
    'UPDATE receipt_sequences SET last_number = ? WHERE tenant_id = ?',
    [newNumber, tenantId]
  );
  return newNumber;
}

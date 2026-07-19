import { describe, it, expect, vi } from 'vitest';
import type { PoolConnection } from 'mysql2/promise';
import { nextReceiptNumber } from '../../services/sequences.js';

// REQ-GOBD-002 (UC-03/06): Bon-Nummern lückenlos und fortlaufend aus
// receipt_sequences via SELECT … FOR UPDATE — innerhalb einer TX.

function mockConn(lastNumber: number | null) {
  let current = lastNumber;
  const execute = vi.fn(async (sql: string, params: unknown[]) => {
    if (sql.includes('SELECT')) {
      return [current === null ? [] : [{ last_number: current }], []];
    }
    // UPDATE: Zustand übernehmen, damit Folge-Aufrufe fortlaufend zählen
    current = params[0] as number;
    return [{ affectedRows: 1 }, []];
  });
  return { conn: { execute } as unknown as PoolConnection, execute };
}

describe('nextReceiptNumber', () => {
  it('inkrementiert: last_number 41 → 42 und schreibt 42 zurück', async () => {
    const { conn, execute } = mockConn(41);
    const num = await nextReceiptNumber(7, conn);
    expect(num).toBe(42);
    const updateCall = execute.mock.calls.find(([sql]) => (sql as string).startsWith('UPDATE'));
    expect(updateCall![1]).toEqual([42, 7]);
  });

  it('wirft mit tenant_id wenn Sequenz-Zeile fehlt (kein stilles 1-Starten)', async () => {
    const { conn } = mockConn(null);
    await expect(nextReceiptNumber(99, conn)).rejects.toThrow('tenant_id=99');
  });

  it('SELECT nutzt FOR UPDATE (Regressionsschutz Lückenlosigkeit)', async () => {
    const { conn, execute } = mockConn(0);
    await nextReceiptNumber(1, conn);
    const selectCall = execute.mock.calls.find(([sql]) => (sql as string).includes('SELECT'));
    expect(selectCall![0]).toContain('FOR UPDATE');
  });

  it('UPDATE ist tenant-gescoped', async () => {
    const { conn, execute } = mockConn(5);
    await nextReceiptNumber(3, conn);
    const updateCall = execute.mock.calls.find(([sql]) => (sql as string).startsWith('UPDATE'));
    expect(updateCall![0]).toContain('tenant_id = ?');
    expect((updateCall![1] as unknown[])[1]).toBe(3);
  });

  it('zwei Aufrufe hintereinander zählen fortlaufend: 42, 43', async () => {
    const { conn } = mockConn(41);
    expect(await nextReceiptNumber(7, conn)).toBe(42);
    expect(await nextReceiptNumber(7, conn)).toBe(43);
  });
});

import { describe, it, expect, vi } from 'vitest';
import type { Pool } from 'mysql2/promise';
import { buildZReportData } from '../../controllers/sessionsController.js';

// REQ-GOBD-011 (UC-09/12): Z-Bericht-Aggregation — Fixture-basiert über
// Mock-Executor. Reihenfolge der Queries in buildZReportData:
// payments → orderCount → vatRows → discountRow → cancellationRow → movements.

type Rows = Array<Record<string, unknown>>;

function mockExecutor(results: Rows[]) {
  let call = 0;
  const execute = vi.fn(async () => [results[call++] ?? [], []]);
  return { exec: { execute } as unknown as Pool, execute };
}

// MariaDB liefert SUM()/COUNT() über DECIMAL als String — Fixtures simulieren das.
function fixtures(overrides: Partial<Record<'payments' | 'orderCount' | 'vat' | 'discount' | 'cancellation' | 'movements', Rows>> = {}): Rows[] {
  return [
    overrides.payments     ?? [
      { method: 'cash', total_amount_cents: '4400', order_count: '2' },
      { method: 'card', total_amount_cents: '2950', order_count: '2' },
    ],
    overrides.orderCount   ?? [{ total_orders: '3' }],
    overrides.vat          ?? [{ vat_7_gross_cents: '350', vat_19_gross_cents: '7000' }],
    overrides.discount     ?? [{ total_discount_cents: '200' }],
    overrides.cancellation ?? [{ cancellation_count: '1' }],
    overrides.movements    ?? [
      { type: 'deposit',    total_cents: '500' },
      { type: 'withdrawal', total_cents: '2000' },
    ],
  ];
}

describe('buildZReportData', () => {
  it('total_revenue = Summe über alle Zahlungsmethoden, als Number', async () => {
    const { exec } = mockExecutor(fixtures());
    const report = await buildZReportData(1, 1, exec);
    expect(report.total_revenue_cents).toBe(7350);
    expect(typeof report.total_revenue_cents).toBe('number');
  });

  it('payments-Shape: method, total_amount_cents, order_count — DECIMAL-Strings konvertiert', async () => {
    const { exec } = mockExecutor(fixtures());
    const report = await buildZReportData(1, 1, exec);
    expect(report.payments).toEqual([
      { method: 'cash', total_amount_cents: 4400, order_count: 2 },
      { method: 'card', total_amount_cents: 2950, order_count: 2 },
    ]);
  });

  it('Storno-Session: alles nettet auf 0, 0-MwSt-Sätze fallen aus vat_breakdown', async () => {
    const { exec } = mockExecutor(fixtures({
      payments:     [{ method: 'cash', total_amount_cents: '0', order_count: '1' }],
      orderCount:   [{ total_orders: '1' }],
      vat:          [{ vat_7_gross_cents: '0', vat_19_gross_cents: '0' }],
      cancellation: [{ cancellation_count: '1' }],
    }));
    const report = await buildZReportData(1, 1, exec);
    expect(report.total_revenue_cents).toBe(0);
    expect(report.vat_breakdown).toEqual([]);
    expect(report.cancellation_count).toBe(1);
  });

  it('vat_breakdown-Shape: {vat_rate, net_plus_vat_cents}, 7 vor 19', async () => {
    const { exec } = mockExecutor(fixtures());
    const report = await buildZReportData(1, 1, exec);
    expect(report.vat_breakdown).toEqual([
      { vat_rate: '7',  net_plus_vat_cents: 350 },
      { vat_rate: '19', net_plus_vat_cents: 7000 },
    ]);
  });

  it('total_orders kommt aus dem DISTINCT-Count (Mixed-Payment zählt 1×)', async () => {
    // 1 Order gemischt bezahlt → payments hat 2 Zeilen mit order_count je 1,
    // maßgeblich ist die separate DISTINCT-Query
    const { exec } = mockExecutor(fixtures({
      payments: [
        { method: 'cash', total_amount_cents: '1000', order_count: '1' },
        { method: 'card', total_amount_cents: '2000', order_count: '1' },
      ],
      orderCount: [{ total_orders: '1' }],
    }));
    const report = await buildZReportData(1, 1, exec);
    expect(report.total_orders).toBe(1);
  });

  it('movements-Mapping deposit/withdrawal als Number', async () => {
    const { exec } = mockExecutor(fixtures());
    const report = await buildZReportData(1, 1, exec);
    expect(report.movements).toEqual([
      { type: 'deposit',    total_cents: 500 },
      { type: 'withdrawal', total_cents: 2000 },
    ]);
  });

  it('leere Session: alle Aggregatte 0, keine NaN aus fehlenden Rows', async () => {
    const { exec } = mockExecutor([[], [], [], [], [], []]);
    const report = await buildZReportData(1, 1, exec);
    expect(report).toEqual({
      payments:             [],
      vat_breakdown:        [],
      total_revenue_cents:  0,
      total_orders:         0,
      total_discount_cents: 0,
      cancellation_count:   0,
      movements:            [],
    });
  });

  it('negative vat-Summen (Folgetag-Storno-Session) erscheinen im Breakdown', async () => {
    const { exec } = mockExecutor(fixtures({
      vat: [{ vat_7_gross_cents: '0', vat_19_gross_cents: '-2849' }],
    }));
    const report = await buildZReportData(1, 1, exec);
    expect(report.vat_breakdown).toEqual([{ vat_rate: '19', net_plus_vat_cents: -2849 }]);
  });
});

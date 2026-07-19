import { describe, it, expect } from 'vitest';
import { validateSplitPartition } from '../../controllers/splitBillController.js';

// REQ-GELD-004 (UC-06): jedes Item in genau einem Split,
// je Split Zahlungssumme == Item-Summe.

const items = [
  { id: 1, subtotal_cents: 2500 },
  { id: 2, subtotal_cents: 1999 },
  { id: 3, subtotal_cents: 350 },
];

describe('validateSplitPartition', () => {
  it('akzeptiert gültigen 2er-Split (gemischte Zahlarten, Summe exakt)', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1, 3], payments: [{ method: 'cash', amount_cents: 2850 }] },
      { order_item_ids: [2],    payments: [{ method: 'cash', amount_cents: 1000 }, { method: 'card', amount_cents: 999 }] },
    ]);
    expect(result).toEqual({ ok: true });
  });

  it('lehnt unbekannte Item-ID ab', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1, 2, 3, 99], payments: [{ method: 'cash', amount_cents: 4849 }] },
    ]);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('99');
  });

  it('lehnt Item in zwei Splits ab (Doppelbezahlung)', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1, 2], payments: [{ method: 'cash', amount_cents: 4499 }] },
      { order_item_ids: [2, 3], payments: [{ method: 'card', amount_cents: 2349 }] },
    ]);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('mehreren Splits');
  });

  it('lehnt fehlendes Item ab (unvollständige Partition)', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1], payments: [{ method: 'cash', amount_cents: 2500 }] },
      { order_item_ids: [2], payments: [{ method: 'card', amount_cents: 1999 }] },
    ]);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('3');
  });

  it('lehnt Zahlungssumme mit 1 Cent Abweichung ab — mit expected/received', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1, 2, 3], payments: [{ method: 'cash', amount_cents: 4848 }] },
    ]);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.expected_cents).toBe(4849);
      expect(result.received_cents).toBe(4848);
    }
  });

  it('meldet den ersten fehlerhaften Split mit 1-basiertem Index', () => {
    const result = validateSplitPartition(items, [
      { order_item_ids: [1],    payments: [{ method: 'cash', amount_cents: 2500 }] },
      { order_item_ids: [2, 3], payments: [{ method: 'card', amount_cents: 9999 }] },
    ]);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain('Split 2');
  });

  it('voll rabattiertes Item (subtotal 0) muss trotzdem zugeordnet sein', () => {
    const withFree = [...items, { id: 4, subtotal_cents: 0 }];
    // fehlt → unvollständig
    const missing = validateSplitPartition(withFree, [
      { order_item_ids: [1, 2, 3], payments: [{ method: 'cash', amount_cents: 4849 }] },
    ]);
    expect(missing.ok).toBe(false);
    // zugeordnet → gültig, 0 Cent ändern die Summe nicht
    const covered = validateSplitPartition(withFree, [
      { order_item_ids: [1, 2, 3, 4], payments: [{ method: 'cash', amount_cents: 4849 }] },
    ]);
    expect(covered).toEqual({ ok: true });
  });
});

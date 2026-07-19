import { describe, it, expect } from 'vitest';
import { centsToFiskaly, buildAmountsPerVatRate, aggregatePaymentTypes } from '../../services/fiskaly.js';

// REQ-TSE-002/003 (UC-15): Beträge als String mit 2 Dezimalstellen,
// amounts_per_vat_rate (Singular!) mit required amount + excl_vat_amounts,
// 0-Sätze weggelassen.

describe('centsToFiskaly', () => {
  it('formatiert Cent als String mit 2 Dezimalstellen', () => {
    expect(centsToFiskaly(3050)).toBe('30.50');
    expect(centsToFiskaly(0)).toBe('0.00');
    expect(centsToFiskaly(5)).toBe('0.05');
    expect(centsToFiskaly(100000)).toBe('1000.00');
  });

  it('negiert für Storno korrekt', () => {
    expect(centsToFiskaly(-3050)).toBe('-30.50');
  });

  it('keine Float-Artefakte bei typischen Beträgen', () => {
    // 19,99 € und ähnliche Beträge sind klassische Binär-Float-Fallen
    expect(centsToFiskaly(1999)).toBe('19.99');
    expect(centsToFiskaly(2849)).toBe('28.49');
    expect(centsToFiskaly(1)).toBe('0.01');
  });
});

describe('buildAmountsPerVatRate', () => {
  it('19 %: 1,00 € → amount 1.00, excl 0.84 + 0.16 (Netto+MwSt == Brutto Cent-genau)', () => {
    const result = buildAmountsPerVatRate(0, 100);
    expect(result).toEqual([
      {
        vat_rate: 'NORMAL',
        amount:   '1.00',
        excl_vat_amounts: { amount: '0.84', vat_amount: '0.16' },
      },
    ]);
  });

  it('7 %: 1,07 € → amount 1.07, excl 1.00 + 0.07', () => {
    const result = buildAmountsPerVatRate(107, 0);
    expect(result).toEqual([
      {
        vat_rate: 'REDUCED_1',
        amount:   '1.07',
        excl_vat_amounts: { amount: '1.00', vat_amount: '0.07' },
      },
    ]);
  });

  it('gemischt: NORMAL vor REDUCED_1, beide Einträge vollständig', () => {
    const result = buildAmountsPerVatRate(350, 2999);
    expect(result.map(e => e.vat_rate)).toEqual(['NORMAL', 'REDUCED_1']);
    for (const entry of result) {
      // amount ist Pflichtfeld (Fiskaly-Schema) — required in jedem Eintrag
      expect(entry.amount).toBeTruthy();
      expect(entry.excl_vat_amounts.amount).toBeTruthy();
      expect(entry.excl_vat_amounts.vat_amount).toBeTruthy();
    }
  });

  it('Netto + MwSt == Brutto für krumme Beträge (beide Sätze)', () => {
    for (const gross of [199, 2849, 9999, 12345]) {
      for (const [vat7, vat19] of [[gross, 0], [0, gross]]) {
        const [entry] = buildAmountsPerVatRate(vat7, vat19);
        const net = Math.round(parseFloat(entry.excl_vat_amounts.amount) * 100);
        const tax = Math.round(parseFloat(entry.excl_vat_amounts.vat_amount) * 100);
        expect(net + tax).toBe(gross);
      }
    }
  });

  it('0-Beträge werden weggelassen', () => {
    expect(buildAmountsPerVatRate(0, 0)).toEqual([]);
    expect(buildAmountsPerVatRate(0, 500).map(e => e.vat_rate)).toEqual(['NORMAL']);
    expect(buildAmountsPerVatRate(500, 0).map(e => e.vat_rate)).toEqual(['REDUCED_1']);
  });
});

describe('aggregatePaymentTypes', () => {
  it('summiert cash-Zahlungen zu CASH, card zu NON_CASH', () => {
    const result = aggregatePaymentTypes([
      { method: 'cash', amount_cents: 1000 },
      { method: 'cash', amount_cents: 500 },
      { method: 'card', amount_cents: 1349 },
    ]);
    expect(result).toEqual([
      { payment_type: 'CASH',     amount: '15.00' },
      { payment_type: 'NON_CASH', amount: '13.49' },
    ]);
  });

  it('nur eine Methode → nur ein Eintrag', () => {
    expect(aggregatePaymentTypes([{ method: 'card', amount_cents: 2500 }]))
      .toEqual([{ payment_type: 'NON_CASH', amount: '25.00' }]);
  });
});

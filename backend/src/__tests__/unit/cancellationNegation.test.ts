import { describe, it, expect } from 'vitest';
import { buildCancellationValues } from '../../controllers/cancellationsController.js';

// REQ-GOBD-004 (UC-07/12): Storno = Gegenbuchung mit negierten Beträgen +
// negativen payments je Original-Zahlungsmittel — Original + Storno == 0
// in allen SUM()-Aggregationen.

const original = {
  vat_7_net_cents:   327,   // 3,50 € @ 7 %
  vat_7_tax_cents:   23,
  vat_19_net_cents:  2100,  // 24,99 € @ 19 %
  vat_19_tax_cents:  399,
  total_gross_cents: 2849,
};

describe('buildCancellationValues', () => {
  it('negiert alle vat_*- und total-Beträge', () => {
    const { negatedAmounts } = buildCancellationValues(original, [{ method: 'cash', amount_cents: 2849 }]);
    expect(negatedAmounts).toEqual({
      vat_7_net_cents:   -327,
      vat_7_tax_cents:   -23,
      vat_19_net_cents:  -2100,
      vat_19_tax_cents:  -399,
      total_gross_cents: -2849,
    });
  });

  it('Invariante: Original + Storno == 0 je Feld (gemischte MwSt)', () => {
    const { negatedAmounts } = buildCancellationValues(original, [{ method: 'card', amount_cents: 2849 }]);
    for (const key of Object.keys(original) as Array<keyof typeof original>) {
      expect(original[key] + negatedAmounts[key]).toBe(0);
    }
  });

  it('negiert payments je Methode einzeln (Gemischt-Zahlung)', () => {
    const { negatedPayments } = buildCancellationValues(original, [
      { method: 'cash', amount_cents: 1000 },
      { method: 'card', amount_cents: 1849 },
    ]);
    expect(negatedPayments).toEqual([
      { method: 'cash', amount_cents: -1000 },
      { method: 'card', amount_cents: -1849 },
    ]);
  });

  it('Fallback ohne Original-payments: eine cash-Zeile über den Gesamtbetrag', () => {
    const { tsePayments, negatedPayments } = buildCancellationValues(original, []);
    expect(tsePayments).toEqual([{ method: 'cash', amount_cents: 2849 }]);
    expect(negatedPayments).toEqual([{ method: 'cash', amount_cents: -2849 }]);
  });

  it('tsePayments bleiben positiv (TSE-CANCELLATION braucht Original-Beträge)', () => {
    const { tsePayments } = buildCancellationValues(original, [
      { method: 'cash', amount_cents: 1000 },
      { method: 'card', amount_cents: 1849 },
    ]);
    expect(tsePayments.every(p => p.amount_cents > 0)).toBe(true);
  });

  it('Summe der negatedPayments == −total_gross_cents', () => {
    const { negatedPayments } = buildCancellationValues(original, [
      { method: 'cash', amount_cents: 849 },
      { method: 'card', amount_cents: 2000 },
    ]);
    const sum = negatedPayments.reduce((s, p) => s + p.amount_cents, 0);
    expect(sum).toBe(-original.total_gross_cents);
  });

  it('0-Cent-Bon: Negation bleibt 0 (kein −0-Artefakt in Summen)', () => {
    const zero = { vat_7_net_cents: 0, vat_7_tax_cents: 0, vat_19_net_cents: 0, vat_19_tax_cents: 0, total_gross_cents: 0 };
    const { negatedAmounts, negatedPayments } = buildCancellationValues(zero, []);
    expect(negatedAmounts.total_gross_cents + zero.total_gross_cents).toBe(0);
    expect(negatedPayments[0].amount_cents + zero.total_gross_cents).toBe(0);
  });
});

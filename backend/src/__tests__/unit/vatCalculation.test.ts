import { describe, it, expect } from 'vitest';
import { calcVat, buildVatBreakdown } from '../../controllers/paymentsController.js';

describe('calcVat — MwSt-Berechnung (§ 14 UStG)', () => {
  describe('19%', () => {
    it('berechnet Netto und Steuer für 11,90€', () => {
      const { netCents, taxCents } = calcVat(1190, '19');
      expect(netCents).toBe(1000);   // 11,90 / 1,19 = 10,00
      expect(taxCents).toBe(190);    // 11,90 - 10,00 = 1,90
    });

    it('berechnet korrekt für 1€ (gerundeter Cent)', () => {
      const { netCents, taxCents } = calcVat(100, '19');
      expect(netCents).toBe(84);     // 1,00 / 1,19 = 0,8403... → 84 Cent
      expect(taxCents).toBe(16);     // 100 - 84 = 16
    });

    it('brutto = netto + steuer (kein Rundungsfehler)', () => {
      for (const gross of [199, 250, 1500, 2990, 9999]) {
        const { netCents, taxCents } = calcVat(gross, '19');
        expect(netCents + taxCents).toBe(gross);
      }
    });

    it('0 Cent ergibt 0 Netto und 0 Steuer', () => {
      const { netCents, taxCents } = calcVat(0, '19');
      expect(netCents).toBe(0);
      expect(taxCents).toBe(0);
    });
  });

  describe('7%', () => {
    it('berechnet Netto und Steuer für 1,07€', () => {
      const { netCents, taxCents } = calcVat(107, '7');
      expect(netCents).toBe(100);   // 1,07 / 1,07 = 1,00
      expect(taxCents).toBe(7);
    });

    it('berechnet korrekt für 2€', () => {
      const { netCents, taxCents } = calcVat(200, '7');
      expect(netCents).toBe(187);   // 2,00 / 1,07 = 1,869... → 187 Cent
      expect(taxCents).toBe(13);
    });

    it('brutto = netto + steuer (kein Rundungsfehler)', () => {
      for (const gross of [107, 214, 350, 1070, 5000]) {
        const { netCents, taxCents } = calcVat(gross, '7');
        expect(netCents + taxCents).toBe(gross);
      }
    });
  });
});

describe('buildVatBreakdown — Aufschlüsselung mehrerer Positionen', () => {
  it('summiert 19%-Positionen korrekt', () => {
    const items = [
      { vat_rate: '19' as const, subtotal_cents: 1190 },
      { vat_rate: '19' as const, subtotal_cents: 2380 },
    ];
    const vat = buildVatBreakdown(items);
    expect(vat.vat19NetCents).toBe(3000);  // (1000 + 2000)
    expect(vat.vat19TaxCents).toBe(570);   // (190 + 380)
    expect(vat.vat7NetCents).toBe(0);
    expect(vat.vat7TaxCents).toBe(0);
  });

  it('summiert gemischte MwSt-Sätze korrekt', () => {
    const items = [
      { vat_rate: '19' as const, subtotal_cents: 1190 },  // 10,00 + 1,90
      { vat_rate: '7'  as const, subtotal_cents: 107  },  // 1,00 + 0,07
    ];
    const vat = buildVatBreakdown(items);
    expect(vat.vat19NetCents).toBe(1000);
    expect(vat.vat19TaxCents).toBe(190);
    expect(vat.vat7NetCents).toBe(100);
    expect(vat.vat7TaxCents).toBe(7);
  });

  it('leere Liste ergibt alles 0', () => {
    const vat = buildVatBreakdown([]);
    expect(vat.vat7NetCents).toBe(0);
    expect(vat.vat7TaxCents).toBe(0);
    expect(vat.vat19NetCents).toBe(0);
    expect(vat.vat19TaxCents).toBe(0);
  });

  it('Summe netto + steuer = brutto für alle Positionen', () => {
    const items = [
      { vat_rate: '19' as const, subtotal_cents: 2990 },
      { vat_rate: '7'  as const, subtotal_cents: 500  },
      { vat_rate: '19' as const, subtotal_cents: 149  },
    ];
    const vat = buildVatBreakdown(items);
    const total19 = items.filter(i => i.vat_rate === '19').reduce((s, i) => s + i.subtotal_cents, 0);
    const total7  = items.filter(i => i.vat_rate === '7' ).reduce((s, i) => s + i.subtotal_cents, 0);
    expect(vat.vat19NetCents + vat.vat19TaxCents).toBe(total19);
    expect(vat.vat7NetCents  + vat.vat7TaxCents).toBe(total7);
  });
});

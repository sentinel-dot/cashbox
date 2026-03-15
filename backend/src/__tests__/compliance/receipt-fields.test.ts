/**
 * Compliance-Tests: KassenSichV + GoBD + §14 UStG Pflichtfelder
 *
 * Diese Tests prüfen, dass validateReceiptFields() alle gesetzlichen
 * Anforderungen korrekt erkennt. Sie laufen in npm test (kein DB nötig).
 */
import { describe, it, expect } from 'vitest';
import { validateReceiptFields, buildReceiptData, type ReceiptData } from '../../services/receipts.js';

// ─── Hilfsfunktion: vollständigen Minimal-Bon bauen ───────────────────────────

function makeReceipt(overrides: Partial<ReceiptData> = {}): ReceiptData {
  const base: ReceiptData = {
    id:             1,
    receipt_number: 1,
    status:         'active',
    is_split_receipt:        false,
    is_cancellation:         false,
    original_receipt_number: null,
    cancellation_reason:     null,

    tenant: {
      name:       'Shishabar GmbH',
      address:    'Musterstr. 1, 10115 Berlin',
      vat_id:     'DE123456789',
      tax_number: null,
    },

    device: { id: 1, name: 'iPad 1' },
    created_at: '2026-03-14T10:00:00.000Z',

    items: [{
      product_name:        'Shisha Groß',
      product_price_cents: 2500,
      vat_rate:            '19',
      quantity:            1,
      subtotal_cents:      2500,
      discount_cents:      0,
      discount_reason:     null,
    }],

    vat_7_net_cents:  0,
    vat_7_tax_cents:  0,
    vat_19_net_cents: 2101,
    vat_19_tax_cents: 399,
    total_gross_cents: 2500,

    payments: [{ method: 'cash', amount_cents: 2500 }],

    tse_pending:           false,
    tse_transaction_id:    'tx-uuid-1234',
    tse_serial_number:     'AAA0001-TSS',
    tse_signature:         'BASE64SIGNATUREDATA==',
    tse_counter:           42,
    tse_transaction_start: '2026-03-14T10:00:00.000Z',
    tse_transaction_end:   '2026-03-14T10:00:01.000Z',
    qr_code_data:          'V0;AAA0001-TSS;42;2026-03-14T10:00:00.000Z;2026-03-14T10:00:01.000Z;25.00;1;GNATUREDATA==',
  };
  return { ...base, ...overrides };
}

// ─── Happy Path ───────────────────────────────────────────────────────────────

describe('validateReceiptFields — vollständiger Bon', () => {
  it('valider Bon besteht Prüfung', () => {
    const result = validateReceiptFields(makeReceipt());
    expect(result.valid).toBe(true);
    expect(result.missingFields).toHaveLength(0);
  });

  it('MwSt-Invariante: 7% netto + 7% steuer + 19% netto + 19% steuer = gesamt', () => {
    // 0 + 0 + 2101 + 399 = 2500 ✓
    const result = validateReceiptFields(makeReceipt());
    expect(result.valid).toBe(true);
  });

  it('Zahlungssumme = total_gross_cents', () => {
    const result = validateReceiptFields(makeReceipt());
    expect(result.valid).toBe(true);
  });
});

// ─── §14 UStG: Unternehmensangaben ───────────────────────────────────────────

describe('validateReceiptFields — §14 UStG Unternehmensangaben', () => {
  it('schlägt fehl wenn tenant.name fehlt', () => {
    const r = makeReceipt({ tenant: { name: '', address: 'X', vat_id: 'DE1', tax_number: null } });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tenant.name');
  });

  it('schlägt fehl wenn tenant.address fehlt', () => {
    const r = makeReceipt({ tenant: { name: 'X', address: '', vat_id: 'DE1', tax_number: null } });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tenant.address');
  });

  it('schlägt fehl wenn weder vat_id noch tax_number vorhanden', () => {
    const r = makeReceipt({ tenant: { name: 'X', address: 'Y', vat_id: null, tax_number: null } });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields.some(f => f.includes('vat_id'))).toBe(true);
  });

  it('besteht wenn nur tax_number vorhanden (keine vat_id)', () => {
    const r = makeReceipt({ tenant: { name: 'X', address: 'Y', vat_id: null, tax_number: '12/345/67890' } });
    const result = validateReceiptFields(r);
    // Tax number alone is sufficient
    expect(result.missingFields.some(f => f.includes('vat_id'))).toBe(false);
  });
});

// ─── KassenSichV: Bon-Identifikation ─────────────────────────────────────────

describe('validateReceiptFields — KassenSichV Bon-Identifikation', () => {
  it('schlägt fehl wenn receipt_number 0 ist', () => {
    const r = makeReceipt({ receipt_number: 0 });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('receipt_number');
  });

  it('schlägt fehl wenn created_at fehlt', () => {
    const r = makeReceipt({ created_at: '' });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('created_at');
  });

  it('schlägt fehl wenn device.name fehlt', () => {
    const r = makeReceipt({ device: { id: 1, name: '' } });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('device.name');
  });
});

// ─── KassenSichV: TSE-Felder ──────────────────────────────────────────────────

describe('validateReceiptFields — KassenSichV TSE-Felder', () => {
  it('schlägt fehl wenn tse_serial_number fehlt (nicht pending)', () => {
    const r = makeReceipt({ tse_pending: false, tse_serial_number: null, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tse_serial_number');
  });

  it('schlägt fehl wenn tse_signature fehlt', () => {
    const r = makeReceipt({ tse_pending: false, tse_signature: null, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tse_signature');
  });

  it('schlägt fehl wenn tse_counter null ist', () => {
    const r = makeReceipt({ tse_pending: false, tse_counter: null, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tse_counter');
  });

  it('schlägt fehl wenn tse_transaction_start fehlt', () => {
    const r = makeReceipt({ tse_pending: false, tse_transaction_start: null, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tse_transaction_start');
  });

  it('schlägt fehl wenn tse_transaction_end fehlt', () => {
    const r = makeReceipt({ tse_pending: false, tse_transaction_end: null, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('tse_transaction_end');
  });

  it('schlägt fehl wenn qr_code_data fehlt (nicht pending)', () => {
    const r = makeReceipt({ tse_pending: false, qr_code_data: null });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('qr_code_data');
  });
});

// ─── Offline-Bon (tse_pending = true) ────────────────────────────────────────

describe('validateReceiptFields — Offline-Bon (tse_pending)', () => {
  it('Offline-Bon ist valid (TSE-Felder optional)', () => {
    const r = makeReceipt({
      tse_pending:           true,
      tse_serial_number:     null,
      tse_signature:         null,
      tse_counter:           null,
      tse_transaction_start: null,
      tse_transaction_end:   null,
      qr_code_data:          null,
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(true);
    expect(result.warnings.length).toBeGreaterThan(0);
    expect(result.warnings.some(w => w.includes('TSE-Signatur ausstehend'))).toBe(true);
    expect(result.warnings.some(w => w.includes('QR-Code'))).toBe(true);
  });
});

// ─── GoBD: Rabatte + Storno ───────────────────────────────────────────────────

describe('validateReceiptFields — GoBD Rabatte + Storno', () => {
  it('schlägt fehl wenn discount_cents > 0 aber kein discount_reason', () => {
    const r = makeReceipt({
      items: [{
        product_name: 'Shisha', product_price_cents: 2500, vat_rate: '19',
        quantity: 1, subtotal_cents: 2000,
        discount_cents: 500, discount_reason: null,  // Pflichtfeld fehlt
      }],
      vat_19_net_cents: 1681, vat_19_tax_cents: 319, total_gross_cents: 2000,
      payments: [{ method: 'cash', amount_cents: 2000 }],
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields.some(f => f.includes('discount_reason'))).toBe(true);
  });

  it('schlägt fehl wenn Storno keine original_receipt_number hat', () => {
    const r = makeReceipt({
      is_cancellation:         true,
      original_receipt_number: null,
      cancellation_reason:     'Kunde storniert',
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('original_receipt_number (Pflicht bei Storno, GoBD)');
  });

  it('schlägt fehl wenn Storno keinen reason hat', () => {
    const r = makeReceipt({
      is_cancellation:         true,
      original_receipt_number: 1,
      cancellation_reason:     null,
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields).toContain('cancellation_reason (Pflicht bei Storno, GoBD)');
  });

  it('valider Storno-Bon besteht Prüfung', () => {
    const r = makeReceipt({
      is_cancellation:         true,
      original_receipt_number: 1,
      cancellation_reason:     'Kunde storniert',
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(true);
  });
});

// ─── MwSt-Invariante ─────────────────────────────────────────────────────────

describe('validateReceiptFields — MwSt-Invariante', () => {
  it('schlägt fehl wenn MwSt-Summe nicht = total_gross_cents', () => {
    const r = makeReceipt({
      vat_19_net_cents:  2000,  // falsch: 2000 + 399 ≠ 2500
      vat_19_tax_cents:  399,
      total_gross_cents: 2500,
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields.some(f => f.includes('MwSt-Invariante'))).toBe(true);
  });

  it('schlägt fehl wenn Zahlungssumme ≠ total_gross_cents', () => {
    const r = makeReceipt({
      payments: [{ method: 'cash', amount_cents: 2000 }],  // 2000 ≠ 2500
    });
    const result = validateReceiptFields(r);
    expect(result.valid).toBe(false);
    expect(result.missingFields.some(f => f.includes('Zahlungssumme'))).toBe(true);
  });
});

// ─── buildReceiptData ─────────────────────────────────────────────────────────

describe('buildReceiptData', () => {
  it('erzeugt qr_code_data wenn alle TSE-Felder vorhanden', () => {
    const dbRow = {
      id: 1, receipt_number: 5, status: 'active',
      is_split_receipt: false,
      device_id: 1, device_name: 'iPad 1',
      vat_7_net_cents: 0, vat_7_tax_cents: 0,
      vat_19_net_cents: 2101, vat_19_tax_cents: 399,
      total_gross_cents: 2500,
      tse_pending: false,
      tse_transaction_id:    'tx-1',
      tse_serial_number:     'SN-0001',
      tse_signature:         'ABCDEF1234567890==',
      tse_counter:           7,
      tse_transaction_start: new Date('2026-03-14T10:00:00Z'),
      tse_transaction_end:   new Date('2026-03-14T10:00:01Z'),
      created_at: new Date('2026-03-14T10:00:01Z'),
    };
    const rawJson = {
      tenant: { name: 'X', address: 'Y', vat_id: 'DE1', tax_number: null },
      items: [{ product_name: 'A', product_price_cents: 2500, vat_rate: '19', quantity: 1, subtotal_cents: 2500, discount_cents: 0, discount_reason: null }],
    };
    const payments = [{ method: 'cash', amount_cents: 2500 }];

    const receipt = buildReceiptData(dbRow, rawJson, payments);
    expect(receipt.qr_code_data).not.toBeNull();
    expect(receipt.qr_code_data).toContain('V0');
    expect(receipt.qr_code_data).toContain('SN-0001');
    expect(receipt.qr_code_data).toContain('25.00');
  });

  it('qr_code_data ist null wenn tse_pending=true', () => {
    const dbRow = {
      id: 1, receipt_number: 1, status: 'active',
      is_split_receipt: false,
      device_id: 1, device_name: 'iPad',
      vat_7_net_cents: 0, vat_7_tax_cents: 0,
      vat_19_net_cents: 2101, vat_19_tax_cents: 399,
      total_gross_cents: 2500,
      tse_pending: true,
      tse_transaction_id: null, tse_serial_number: null, tse_signature: null,
      tse_counter: null, tse_transaction_start: null, tse_transaction_end: null,
      created_at: new Date(),
    };
    const receipt = buildReceiptData(dbRow, null, [{ method: 'cash', amount_cents: 2500 }]);
    expect(receipt.qr_code_data).toBeNull();
    expect(receipt.tse_pending).toBe(true);
  });

  it('erkennt Storno-Bon aus raw_receipt_json', () => {
    const dbRow = {
      id: 2, receipt_number: 2, status: 'active',
      is_split_receipt: false,
      device_id: 1, device_name: 'iPad',
      vat_7_net_cents: 0, vat_7_tax_cents: 0,
      vat_19_net_cents: 2101, vat_19_tax_cents: 399,
      total_gross_cents: 2500,
      tse_pending: false,
      tse_transaction_id: 'tx-2', tse_serial_number: 'SN', tse_signature: 'SIG',
      tse_counter: 2, tse_transaction_start: new Date(), tse_transaction_end: new Date(),
      created_at: new Date(),
    };
    const rawJson = {
      cancellation: true,
      original_receipt_number: 1,
      reason: 'Testgrund',
      tenant: { name: 'X', address: 'Y', vat_id: null, tax_number: '12/345/67890' },
      items: [],
    };
    const receipt = buildReceiptData(dbRow, rawJson, [{ method: 'cash', amount_cents: 2500 }]);
    expect(receipt.is_cancellation).toBe(true);
    expect(receipt.original_receipt_number).toBe(1);
    expect(receipt.cancellation_reason).toBe('Testgrund');
  });
});

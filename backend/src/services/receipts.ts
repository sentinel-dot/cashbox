/**
 * Receipt-Service — digitaler Bon (kein Drucker)
 *
 * Baut aus DB-Daten ein vollständig typisiertes ReceiptData-Objekt
 * und prüft alle KassenSichV / GoBD / §14 UStG Pflichtfelder.
 *
 * QR-Code-Format: BSI TR-03153 (vereinfacht, kompatibel mit Fiskaly)
 * SwiftUI: empfängt `qr_code_data`-String und rendert ihn als QR-Code (CoreImage).
 */

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ReceiptItem {
  product_name:        string;
  product_price_cents: number;
  vat_rate:            '7' | '19';
  quantity:            number;
  subtotal_cents:      number;
  discount_cents:      number;
  discount_reason:     string | null;
}

export interface ReceiptPayment {
  method:       'cash' | 'card';
  amount_cents: number;
}

export interface ReceiptData {
  // ─── Identifikation ──────────────────────────────────────────────────────
  id:             number;
  receipt_number: number;
  status:         'active' | 'voided';
  is_split_receipt:    boolean;
  is_cancellation:     boolean;
  original_receipt_number: number | null;  // nur bei Storno
  cancellation_reason:     string | null;  // nur bei Storno

  // ─── §14 UStG: Angaben zum Unternehmen ───────────────────────────────────
  tenant: {
    name:        string;
    address:     string;
    vat_id:      string | null;  // USt-IdNr. oder Steuernummer (mind. eines Pflicht)
    tax_number:  string | null;
  };

  // ─── §6 Abs.1 Nr.6 KassenSichV: Kassensystem-Bezeichnung + ID ────────────
  device: {
    id:   number;
    name: string;
  };

  // ─── Zeitangaben (KassenSichV) ────────────────────────────────────────────
  created_at: string;  // ISO-8601

  // ─── §14 UStG: Positionen ────────────────────────────────────────────────
  items: ReceiptItem[];

  // ─── §14 UStG: MwSt-Aufschlüsselung ─────────────────────────────────────
  vat_7_net_cents:  number;
  vat_7_tax_cents:  number;
  vat_19_net_cents: number;
  vat_19_tax_cents: number;
  total_gross_cents: number;

  // ─── Zahlungsarten (KassenSichV) ─────────────────────────────────────────
  payments: ReceiptPayment[];

  // ─── TSE-Felder (KassenSichV §6) ─────────────────────────────────────────
  tse_pending:           boolean;
  tse_transaction_id:    string | null;
  tse_serial_number:     string | null;
  tse_signature:         string | null;
  tse_counter:           number | null;
  tse_transaction_start: string | null;  // ISO-8601
  tse_transaction_end:   string | null;  // ISO-8601

  // ─── QR-Code (BSI TR-03153) ───────────────────────────────────────────────
  // null wenn tse_pending=true (TSE-Daten fehlen)
  // SwiftUI: CIFilter.qrCodeGenerator mit diesem String → QRCode-Image
  qr_code_data: string | null;
}

export interface ValidationResult {
  valid:         boolean;
  missingFields: string[];
  warnings:      string[];
}

// ─── QR-Code-Daten generieren (BSI TR-03153) ─────────────────────────────────
//
// Format (vereinfacht, Fiskaly-kompatibel):
//   V0;[serial_number];[counter];[tx_start];[tx_end];[amount_euros];[receipt_number];[signature_truncated]
//
// SwiftUI: CIFilter(name: "CIQRCodeGenerator")?.setValue(qr_code_data, forKey: "inputMessage")

function buildQrCodeData(receipt: Omit<ReceiptData, 'qr_code_data'>): string | null {
  if (
    receipt.tse_pending ||
    !receipt.tse_serial_number ||
    !receipt.tse_signature ||
    receipt.tse_counter === null ||
    !receipt.tse_transaction_start ||
    !receipt.tse_transaction_end
  ) {
    return null;  // Offline-Bon: kein QR-Code bis TSE-Signatur vorliegt
  }

  const totalEuros = (receipt.total_gross_cents / 100).toFixed(2);
  // Signatur auf 12 Zeichen kürzen für kompakten QR-Code
  const sigShort   = receipt.tse_signature.slice(-12);

  return [
    'V0',
    receipt.tse_serial_number,
    String(receipt.tse_counter),
    receipt.tse_transaction_start,
    receipt.tse_transaction_end,
    totalEuros,
    String(receipt.receipt_number),
    sigShort,
  ].join(';');
}

// ─── Receipt aus DB-Daten bauen ───────────────────────────────────────────────

/**
 * Baut ein vollständiges ReceiptData-Objekt aus DB-Feldern.
 *
 * @param dbRow     - Zeile aus der `receipts`-Tabelle
 * @param rawJson   - Bereits geparster raw_receipt_json (Snapshot)
 * @param payments  - Aus der `payments`-Tabelle für diesen Receipt
 */
export function buildReceiptData(
  dbRow:    Record<string, any>,
  rawJson:  Record<string, any> | null,
  payments: Array<{ method: string; amount_cents: number }>,
): ReceiptData {
  const isCancel = rawJson?.cancellation === true;

  // Für Storno-Bons: aus raw_receipt_json; für Normalbons: aus DB
  const tenant = rawJson?.tenant ?? {
    name:       dbRow['device_name'] ?? '',  // Fallback — sollte nie nötig sein
    address:    '',
    vat_id:     null,
    tax_number: null,
  };

  const tseStart = dbRow['tse_transaction_start']
    ? (dbRow['tse_transaction_start'] instanceof Date
        ? dbRow['tse_transaction_start'].toISOString()
        : String(dbRow['tse_transaction_start']))
    : null;

  const tseEnd = dbRow['tse_transaction_end']
    ? (dbRow['tse_transaction_end'] instanceof Date
        ? dbRow['tse_transaction_end'].toISOString()
        : String(dbRow['tse_transaction_end']))
    : null;

  const createdAt = dbRow['created_at'] instanceof Date
    ? dbRow['created_at'].toISOString()
    : String(dbRow['created_at'] ?? '');

  const tsePending = dbRow['tse_pending'] === 1 || dbRow['tse_pending'] === true;

  const partial: Omit<ReceiptData, 'qr_code_data'> = {
    id:             dbRow['id'],
    receipt_number: dbRow['receipt_number'],
    status:         dbRow['status'],
    is_split_receipt:        !!(dbRow['is_split_receipt'] === 1 || dbRow['is_split_receipt'] === true),
    is_cancellation:         isCancel,
    original_receipt_number: rawJson?.original_receipt_number ?? null,
    cancellation_reason:     rawJson?.reason ?? null,

    tenant: {
      name:       tenant.name       ?? '',
      address:    tenant.address    ?? '',
      vat_id:     tenant.vat_id     ?? null,
      tax_number: tenant.tax_number ?? null,
    },

    device: {
      id:   dbRow['device_id'],
      name: dbRow['device_name'] ?? '',
    },

    created_at: createdAt,
    items:      (rawJson?.items ?? []) as ReceiptItem[],

    vat_7_net_cents:  dbRow['vat_7_net_cents']  ?? 0,
    vat_7_tax_cents:  dbRow['vat_7_tax_cents']  ?? 0,
    vat_19_net_cents: dbRow['vat_19_net_cents'] ?? 0,
    vat_19_tax_cents: dbRow['vat_19_tax_cents'] ?? 0,
    total_gross_cents: dbRow['total_gross_cents'] ?? 0,

    payments: payments.map(p => ({
      method:       p.method as 'cash' | 'card',
      amount_cents: p.amount_cents,
    })),

    tse_pending:           tsePending,
    tse_transaction_id:    dbRow['tse_transaction_id']    ?? null,
    tse_serial_number:     dbRow['tse_serial_number']     ?? null,
    tse_signature:         dbRow['tse_signature']         ?? null,
    tse_counter:           dbRow['tse_counter']           ?? null,
    tse_transaction_start: tseStart,
    tse_transaction_end:   tseEnd,
  };

  return { ...partial, qr_code_data: buildQrCodeData(partial) };
}

// ─── Pflichtfeld-Validierung (KassenSichV + GoBD + §14 UStG) ─────────────────

/**
 * Prüft alle gesetzlichen Pflichtfelder eines Bons.
 * Wird in Compliance-Tests und vor dem Anzeigen/Archivieren verwendet.
 */
export function validateReceiptFields(receipt: ReceiptData): ValidationResult {
  const missing: string[]  = [];
  const warnings: string[] = [];

  // §14 UStG: Unternehmensangaben
  if (!receipt.tenant.name)    missing.push('tenant.name');
  if (!receipt.tenant.address) missing.push('tenant.address');
  if (!receipt.tenant.vat_id && !receipt.tenant.tax_number) {
    missing.push('tenant.vat_id oder tenant.tax_number (mind. eines Pflicht)');
  }

  // KassenSichV: Bon-Nummer + Datum
  if (!receipt.receipt_number)    missing.push('receipt_number');
  if (!receipt.created_at)        missing.push('created_at');

  // §6 Abs.1 Nr.6 KassenSichV: Kassensystem
  if (!receipt.device.name) missing.push('device.name');
  if (!receipt.device.id)   missing.push('device.id');

  // §14 UStG: Positionen
  if (!receipt.items || receipt.items.length === 0) {
    missing.push('items (mindestens eine Position)');
  }

  // Zahlungsart
  if (!receipt.payments || receipt.payments.length === 0) {
    missing.push('payments (mindestens eine Zahlungsart)');
  }

  // §14 UStG: MwSt-Invariante prüfen
  const vatSum = receipt.vat_7_net_cents  + receipt.vat_7_tax_cents
               + receipt.vat_19_net_cents + receipt.vat_19_tax_cents;
  if (vatSum !== receipt.total_gross_cents) {
    missing.push(`MwSt-Invariante verletzt: ${vatSum} ≠ ${receipt.total_gross_cents}`);
  }

  // Zahlungssumme prüfen
  const paySum = receipt.payments.reduce((s, p) => s + p.amount_cents, 0);
  if (paySum !== receipt.total_gross_cents) {
    missing.push(`Zahlungssumme stimmt nicht: ${paySum} ≠ ${receipt.total_gross_cents}`);
  }

  // GoBD: Rabatte müssen Begründung haben
  for (const item of receipt.items ?? []) {
    if (item.discount_cents > 0 && !item.discount_reason) {
      missing.push(`items[${item.product_name}]: discount_reason fehlt (GoBD-Pflicht)`);
    }
  }

  // KassenSichV: TSE-Felder (Warnung bei tse_pending, Fehler bei abgeschlossenem Bon)
  if (receipt.tse_pending) {
    warnings.push('TSE-Signatur ausstehend — Bon ist rechtlich unvollständig bis zur Nachsignierung');
    warnings.push('Kein QR-Code verfügbar bis TSE-Daten vorliegen');
  } else {
    if (!receipt.tse_serial_number)     missing.push('tse_serial_number');
    if (!receipt.tse_signature)         missing.push('tse_signature');
    if (receipt.tse_counter === null)   missing.push('tse_counter');
    if (!receipt.tse_transaction_start) missing.push('tse_transaction_start');
    if (!receipt.tse_transaction_end)   missing.push('tse_transaction_end');
    if (!receipt.qr_code_data)          missing.push('qr_code_data');
  }

  // GoBD: Storno muss Original-Bon-Nummer enthalten
  if (receipt.is_cancellation && !receipt.original_receipt_number) {
    missing.push('original_receipt_number (Pflicht bei Storno, GoBD)');
  }
  if (receipt.is_cancellation && !receipt.cancellation_reason) {
    missing.push('cancellation_reason (Pflicht bei Storno, GoBD)');
  }

  return {
    valid:         missing.length === 0,
    missingFields: missing,
    warnings,
  };
}

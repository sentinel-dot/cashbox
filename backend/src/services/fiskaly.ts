import { v4 as uuidv4 } from 'uuid';
import { db } from '../db/index.js';
import { writeAuditLog } from './audit.js';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface TseTransactionParams {
  tenantId:        number;
  deviceId:        number;
  orderId:         number;
  userId:          number;
  tssId:           string;
  clientId:        string;
  vat7GrossCents:  number;
  vat19GrossCents: number;
  payments:        Array<{ method: 'cash' | 'card'; amount_cents: number }>;
  receiptType?:    'RECEIPT' | 'CANCELLATION';  // default: RECEIPT
  idempotencyKey?: string;  // UUID — für Recovery bei Timeout
}

export interface TseTransactionResult {
  pending:              boolean;
  idempotencyKey:       string;
  tseTransactionId?:    string;
  tseSerialNumber?:     string;
  tseSignature?:        string;
  tseCounter?:          number;
  tseTransactionStart?: Date;
  tseTransactionEnd?:   Date;
}

// ─── Fiskaly API Client ───────────────────────────────────────────────────────

const FISKALY_BASE_URL   = process.env['FISKALY_BASE_URL']   ?? 'https://kassensichv-middleware.fiskaly.com/api/v2';
const FISKALY_API_KEY    = process.env['FISKALY_API_KEY']    ?? '';
const FISKALY_API_SECRET = process.env['FISKALY_API_SECRET'] ?? '';

let _token: string | null = null;
let _tokenExpiry = 0;

async function getToken(): Promise<string> {
  if (_token && Date.now() < _tokenExpiry - 60_000) return _token;

  const res = await fetch(`${FISKALY_BASE_URL}/auth`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ api_key: FISKALY_API_KEY, api_secret: FISKALY_API_SECRET }),
  });
  if (!res.ok) throw Object.assign(new Error(`Fiskaly auth failed: ${res.status}`), { status: res.status });

  const data = await res.json() as { access_token: string; expires_in: number };
  _token = data.access_token;
  _tokenExpiry = Date.now() + data.expires_in * 1000;
  return _token;
}

async function fiskalyFetch(method: string, path: string, body?: unknown): Promise<{ status: number; data: any }> {
  const token = await getToken();
  const res = await fetch(`${FISKALY_BASE_URL}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data = res.status !== 204 ? await res.json() : null;
  return { status: res.status, data };
}

// ─── Hilfsfunktion: Cent → Fiskaly-String ("30.50") ─────────────────────────

function centsToFiskaly(cents: number): string {
  return (cents / 100).toFixed(2);
}

// ─── TSE-TX Step 1: starten ───────────────────────────────────────────────────

async function startTx(tssId: string, txId: string, clientId: string): Promise<void> {
  const { status } = await fiskalyFetch('PUT', `/tss/${tssId}/tx/${txId}?tx_revision=1`, {
    state:     'ACTIVE',
    client_id: clientId,
  });
  if (status === 409) return;  // bereits gestartet — idempotent
  if (status < 200 || status >= 300) {
    throw Object.assign(new Error(`Fiskaly startTx failed: ${status}`), { status });
  }
}

// ─── Hilfsfunktion: payments aggregieren → Fiskaly amounts_per_payment_types ─

function aggregatePaymentTypes(
  payments: Array<{ method: 'cash' | 'card'; amount_cents: number }>
): Array<{ payment_type: string; amount: string }> {
  const totals: Record<string, number> = {};
  for (const p of payments) {
    const key = p.method === 'cash' ? 'CASH' : 'NON_CASH';
    totals[key] = (totals[key] ?? 0) + p.amount_cents;
  }
  return Object.entries(totals).map(([payment_type, cents]) => ({
    payment_type,
    amount: centsToFiskaly(cents),
  }));
}

// ─── TSE-TX Step 2: befüllen ──────────────────────────────────────────────────

async function updateTx(
  tssId: string, txId: string, clientId: string,
  params: TseTransactionParams
): Promise<void> {
  // Idempotenz: aktuelle Revision lesen, damit Retry nach Timeout nicht mit 409 scheitert
  const { status: getStatus, data: current } = await fiskalyFetch('GET', `/tss/${tssId}/tx/${txId}`);
  if (getStatus === 200 && (current?.state === 'FINISHED')) return; // bereits fertig — nichts tun
  const revision = (getStatus === 200 && current?.latest_revision)
    ? current.latest_revision + 1
    : 2;

  // Fiskaly: amounts_per_vat_rate — amount (Brutto, required) + excl_vat_amounts (Netto + MwSt, optional aber empfohlen)
  const amountsPerVatRates = [];
  if (params.vat19GrossCents > 0) {
    const netCents = Math.round((params.vat19GrossCents * 100) / 119);
    amountsPerVatRates.push({
      vat_rate: 'NORMAL',
      amount:   centsToFiskaly(params.vat19GrossCents),
      excl_vat_amounts: {
        amount:     centsToFiskaly(netCents),
        vat_amount: centsToFiskaly(params.vat19GrossCents - netCents),
      },
    });
  }
  if (params.vat7GrossCents > 0) {
    const netCents = Math.round((params.vat7GrossCents * 100) / 107);
    amountsPerVatRates.push({
      vat_rate: 'REDUCED_1',
      amount:   centsToFiskaly(params.vat7GrossCents),
      excl_vat_amounts: {
        amount:     centsToFiskaly(netCents),
        vat_amount: centsToFiskaly(params.vat7GrossCents - netCents),
      },
    });
  }

  const reqBody = {
    state:     'ACTIVE',
    client_id: clientId,
    schema: {
      standard_v1: {
        receipt: {
          receipt_type:            params.receiptType ?? 'RECEIPT',
          amounts_per_vat_rate:    amountsPerVatRates,
          amounts_per_payment_type: aggregatePaymentTypes(params.payments),
        },
      },
    },
  };
  const { status } = await fiskalyFetch('PUT', `/tss/${tssId}/tx/${txId}?tx_revision=${revision}`, reqBody);
  if (status < 200 || status >= 300) {
    throw Object.assign(new Error(`Fiskaly updateTx failed: ${status}`), { status });
  }
}

// ─── TSE-TX Step 3: abschließen (mit Idempotenz-Check) ───────────────────────

function mapFiskalyResponse(data: any): Omit<TseTransactionResult, 'pending' | 'idempotencyKey'> {
  return {
    tseTransactionId:    data._id ?? data.id,
    tseSerialNumber:     data.tss_serial_number,
    tseSignature:        data.signature?.value,
    tseCounter:          data.signature?.counter,
    tseTransactionStart: new Date((data.time_start ?? 0) * 1000),
    tseTransactionEnd:   new Date((data.time_end   ?? 0) * 1000),
  };
}

async function finishTx(
  tssId: string, txId: string, clientId: string, revision: number,
  params: TseTransactionParams
): Promise<Omit<TseTransactionResult, 'pending' | 'idempotencyKey'>> {
  // Idempotenz: prüfen ob TX bereits FINISHED (Timeout-Recovery)
  const { status: getStatus, data: existing } = await fiskalyFetch('GET', `/tss/${tssId}/tx/${txId}`);
  if (getStatus === 200 && existing?.state === 'FINISHED') {
    return mapFiskalyResponse(existing);
  }

  // Aktuellen Revision-Stand berücksichtigen
  const currentRevision = (getStatus === 200 && existing?.latest_revision)
    ? existing.latest_revision + 1
    : revision;

  // Fiskaly erfordert vollständiges Schema auch beim FINISHED-Request
  const amountsPerVatRates = [];
  if (params.vat19GrossCents > 0) {
    const netCents = Math.round((params.vat19GrossCents * 100) / 119);
    amountsPerVatRates.push({
      vat_rate: 'NORMAL',
      amount:   centsToFiskaly(params.vat19GrossCents),
      excl_vat_amounts: {
        amount:     centsToFiskaly(netCents),
        vat_amount: centsToFiskaly(params.vat19GrossCents - netCents),
      },
    });
  }
  if (params.vat7GrossCents > 0) {
    const netCents = Math.round((params.vat7GrossCents * 100) / 107);
    amountsPerVatRates.push({
      vat_rate: 'REDUCED_1',
      amount:   centsToFiskaly(params.vat7GrossCents),
      excl_vat_amounts: {
        amount:     centsToFiskaly(netCents),
        vat_amount: centsToFiskaly(params.vat7GrossCents - netCents),
      },
    });
  }

  const { status, data } = await fiskalyFetch('PUT', `/tss/${tssId}/tx/${txId}?tx_revision=${currentRevision}`, {
    state:     'FINISHED',
    client_id: clientId,
    schema: {
      standard_v1: {
        receipt: {
          receipt_type:             params.receiptType ?? 'RECEIPT',
          amounts_per_vat_rate:     amountsPerVatRates,
          amounts_per_payment_type: aggregatePaymentTypes(params.payments),
        },
      },
    },
  });
  if (status < 200 || status >= 300) {
    throw Object.assign(new Error(`Fiskaly finishTx failed: ${status}`), { status, data });
  }
  return mapFiskalyResponse(data);
}

// ─── Exponential Backoff ──────────────────────────────────────────────────────

async function withRetry<T>(fn: () => Promise<T>, maxAttempts = 3): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < maxAttempts; i++) {
    try {
      return await fn();
    } catch (err: any) {
      lastErr = err;
      // 4xx (außer 408 Timeout, 429 Rate-Limit): nicht retrybar
      if (err.status && err.status >= 400 && err.status < 500 && err.status !== 408 && err.status !== 429) {
        throw err;
      }
      if (i < maxAttempts - 1) {
        await new Promise(r => setTimeout(r, 200 * Math.pow(2, i)));
      }
    }
  }
  throw lastErr;
}

// ─── Offline-Queue-Eintrag ────────────────────────────────────────────────────

async function enqueueOffline(params: TseTransactionParams, idempotencyKey: string, error: string): Promise<void> {
  await db.execute(
    `INSERT INTO offline_queue (tenant_id, device_id, order_id, payload_json, idempotency_key, status, error_message)
     VALUES (?, ?, ?, ?, ?, 'pending', ?)`,
    [
      params.tenantId, params.deviceId, params.orderId,
      JSON.stringify({
        vat7GrossCents:  params.vat7GrossCents,
        vat19GrossCents: params.vat19GrossCents,
        payments:        params.payments,
      }),
      idempotencyKey,
      error,
    ]
  );
}

// ─── Haupt-Einstiegspunkt ─────────────────────────────────────────────────────

/**
 * Führt eine vollständige Fiskaly-TSE-Transaktion durch (3-stufig).
 *
 * - Kein TSS/Client konfiguriert → Offline (Phase 1 / Test-Modus)
 * - Netzwerkfehler / 5xx → Offline-Fallback + offline_queue-Eintrag
 * - 4xx Validierungsfehler → wirft direkt (kein Receipt soll erstellt werden)
 * - Erfolg → vollständige TSE-Daten für Receipt-INSERT
 *
 * GoBD: Diese Funktion wird VOR dem Receipt-INSERT aufgerufen,
 * damit der Receipt einmalig mit vollständigen TSE-Daten geschrieben wird.
 */
export async function processTseTransaction(params: TseTransactionParams): Promise<TseTransactionResult> {
  const idempotencyKey = params.idempotencyKey ?? uuidv4();

  // Kein TSS/Client konfiguriert (Phase 1 / Sandbox deaktiviert)
  if (!params.tssId || !params.clientId) {
    return { pending: true, idempotencyKey };
  }

  try {
    const tseData = await withRetry(async () => {
      await startTx(params.tssId, idempotencyKey, params.clientId);
      await updateTx(params.tssId, idempotencyKey, params.clientId, params);
      return await finishTx(params.tssId, idempotencyKey, params.clientId, 3, params);
    });

    // Audit-Log (nicht-fatal)
    writeAuditLog({
      tenantId: params.tenantId, userId: params.userId,
      action: 'tse.transaction_finished',
      entityType: 'order', entityId: params.orderId,
      diff: { new: { tse_transaction_id: tseData.tseTransactionId, idempotency_key: idempotencyKey } },
      deviceId: params.deviceId,
    }).catch(() => {});

    return { pending: false, idempotencyKey, ...tseData };
  } catch (err: any) {
    // 4xx Validierungsfehler: kein Fallback, direkt fehlschlagen
    if (err.status && err.status >= 400 && err.status < 500) {
      throw err;
    }

    // Netzwerkfehler / 5xx → Offline-Fallback
    const errorMessage = err.message ?? String(err);
    await enqueueOffline(params, idempotencyKey, errorMessage).catch(() => {});

    writeAuditLog({
      tenantId: params.tenantId, userId: params.userId,
      action: 'tse.offline_fallback',
      entityType: 'order', entityId: params.orderId,
      diff: { new: { idempotency_key: idempotencyKey, error: errorMessage } },
      deviceId: params.deviceId,
    }).catch(() => {});

    return { pending: true, idempotencyKey };
  }
}

// ─── DSFinV-K Export ──────────────────────────────────────────────────────────

export type ExportState = 'PENDING' | 'WORKING' | 'COMPLETED' | 'ERROR' | 'CANCELLED';

export interface DsfinvkExportStatus {
  exportId:  string;
  state:     ExportState;
  exception: string | null;
  timeRequest:    number | null;
  timeExpiration: number | null;
}

/**
 * Startet einen neuen DSFinV-K-Export bei Fiskaly.
 * Datum-Range als Unix-Timestamp (Sekunden).
 * export_id ist eine neue UUID — wird vom Client vorgegeben für Idempotenz.
 */
export async function triggerDsfinvkExport(
  tssId: string,
  exportId: string,
  startDate: Date,
  endDate: Date,
): Promise<DsfinvkExportStatus> {
  const startTs = Math.floor(startDate.getTime() / 1000);
  const endTs   = Math.floor(endDate.getTime()   / 1000);

  const { status, data } = await fiskalyFetch(
    'PUT',
    `/tss/${tssId}/export/${exportId}?start_date=${startTs}&end_date=${endTs}`,
  );

  if (status !== 200) {
    throw Object.assign(
      new Error(`Fiskaly export trigger failed: ${status} ${data?.error ?? ''}`),
      { status, fiskalyError: data?.error }
    );
  }

  return {
    exportId:       data._id ?? exportId,
    state:          data.state,
    exception:      data.exception ?? null,
    timeRequest:    data.time_request    ?? null,
    timeExpiration: data.time_expiration ?? null,
  };
}

/**
 * Fragt den Status eines laufenden DSFinV-K-Exports ab.
 */
export async function getDsfinvkExportStatus(
  tssId: string,
  exportId: string,
): Promise<DsfinvkExportStatus> {
  const { status, data } = await fiskalyFetch('GET', `/tss/${tssId}/export/${exportId}`);

  if (status === 404) {
    throw Object.assign(new Error('Export nicht gefunden.'), { status: 404 });
  }
  if (status !== 200) {
    throw Object.assign(new Error(`Fiskaly export status failed: ${status}`), { status });
  }

  return {
    exportId:       data._id ?? exportId,
    state:          data.state,
    exception:      data.exception ?? null,
    timeRequest:    data.time_request    ?? null,
    timeExpiration: data.time_expiration ?? null,
  };
}

/**
 * Gibt die URL zurück, über die die TAR-Datei direkt von Fiskaly heruntergeladen werden kann.
 * Nur aufrufbar wenn state === 'COMPLETED'.
 */
export function getDsfinvkFileUrl(tssId: string, exportId: string): string {
  return `${FISKALY_BASE_URL}/tss/${tssId}/export/${exportId}/file`;
}

/**
 * Holt das Bearer-Token für direkte Fiskaly-Anfragen (z.B. File-Proxy).
 */
export async function getFiskalyToken(): Promise<string> {
  return getToken();
}

import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { buildReceiptData } from '../services/receipts.js';

// ─── Plan-Limits: Rückblick in Tagen ────────────────────────────────────────

const REPORT_DAYS_LIMIT: Record<string, number> = {
  starter:  30,
  pro:      365,
  business: 3650,
};

// ─── GET /receipts — Listenansicht ──────────────────────────────────────────

const listReceiptsQuerySchema = z.object({
  from:       z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD').optional(),
  to:         z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD').optional(),
  session_id: z.coerce.number().int().positive().optional(),
  limit:      z.coerce.number().int().min(1).max(100).default(50),
  offset:     z.coerce.number().int().nonnegative().default(0),
});

export async function listReceipts(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const parsed = listReceiptsQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(422).json({ error: 'Validierungsfehler.', details: parsed.error.flatten().fieldErrors });
    return;
  }
  const { from, to, session_id, limit, offset } = parsed.data;

  // Plan ermitteln + Datumsbereich prüfen
  const [tenantRows] = await db.execute<any[]>(
    'SELECT plan FROM tenants WHERE id = ?',
    [tenantId]
  );
  const plan = tenantRows[0]?.plan ?? 'starter';
  const maxDays = REPORT_DAYS_LIMIT[plan] ?? 30;
  const earliestAllowed = new Date();
  earliestAllowed.setDate(earliestAllowed.getDate() - maxDays);
  const earliestStr = earliestAllowed.toISOString().slice(0, 10);

  if (from && from < earliestStr) {
    res.status(403).json({
      error: `Plan-Limit: ${plan}-Plan erlaubt maximal ${maxDays} Tage Rückblick (frühestes Datum: ${earliestStr}).`,
    });
    return;
  }

  // Dynamische WHERE-Klausel aufbauen
  const conditions: string[] = ['r.tenant_id = ?'];
  const params: (string | number)[] = [tenantId];

  if (from) { conditions.push('DATE(r.created_at) >= ?'); params.push(from); }
  if (to)   { conditions.push('DATE(r.created_at) <= ?'); params.push(to); }
  if (session_id) { conditions.push('r.session_id = ?'); params.push(session_id); }

  const where = conditions.join(' AND ');

  const [countRows] = await db.execute<any[]>(
    `SELECT COUNT(*) AS total FROM receipts r WHERE ${where}`,
    params
  );
  const total = Number(countRows[0].total);

  const [rows] = await db.execute<any[]>(
    `SELECT
       r.id, r.receipt_number, r.status, r.void_reason,
       r.order_id, r.session_id, r.device_id, r.device_name,
       r.total_gross_cents, r.tip_cents, r.is_takeaway,
       r.is_split_receipt, r.tse_pending, r.created_at
     FROM receipts r
     WHERE ${where}
     ORDER BY r.created_at DESC
     LIMIT ? OFFSET ?`,
    [...params, limit, offset]
  );

  res.json({
    receipts: rows.map(r => ({
      id:               r.id,
      receipt_number:   r.receipt_number,
      status:           r.status,
      void_reason:      r.void_reason ?? null,
      order_id:         r.order_id,
      session_id:       r.session_id,
      device_id:        r.device_id,
      device_name:      r.device_name,
      total_gross_cents: r.total_gross_cents,
      tip_cents:        r.tip_cents,
      is_takeaway:      Boolean(r.is_takeaway),
      is_split_receipt: Boolean(r.is_split_receipt),
      tse_pending:      r.tse_pending === 1 || r.tse_pending === true,
      created_at:       r.created_at,
    })),
    total,
    limit,
    offset,
  });
}

// ─── GET /receipts/:id ────────────────────────────────────────────────────────

export async function getReceipt(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const receiptId = Number(req.params['id']);

  if (!Number.isInteger(receiptId) || receiptId <= 0) {
    res.status(400).json({ error: 'Ungültige Receipt-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    `SELECT
       r.id, r.receipt_number, r.status, r.void_reason,
       r.device_id, r.device_name,
       r.vat_7_net_cents, r.vat_7_tax_cents,
       r.vat_19_net_cents, r.vat_19_tax_cents,
       r.total_gross_cents, r.tip_cents, r.is_takeaway,
       r.tse_transaction_id, r.tse_serial_number, r.tse_signature,
       r.tse_counter, r.tse_transaction_start, r.tse_transaction_end,
       r.tse_pending, r.is_split_receipt, r.raw_receipt_json,
       r.created_at, r.order_id, r.session_id
     FROM receipts r
     WHERE r.id = ? AND r.tenant_id = ?`,
    [receiptId, tenantId]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Bon nicht gefunden.' });
    return;
  }

  const [payments] = await db.execute<any[]>(
    `SELECT p.id, p.method, p.amount_cents, p.tip_cents, p.paid_at
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE p.receipt_id = ? AND r.tenant_id = ?
     ORDER BY p.paid_at ASC`,
    [receiptId, tenantId]
  );

  const r = rows[0];
  const rawJson = r.raw_receipt_json
    ? (typeof r.raw_receipt_json === 'string' ? JSON.parse(r.raw_receipt_json) : r.raw_receipt_json)
    : null;

  res.json({
    id:                  r.id,
    receipt_number:      r.receipt_number,
    status:              r.status,
    void_reason:         r.void_reason ?? null,
    order_id:            r.order_id,
    session_id:          r.session_id,
    device_id:           r.device_id,
    device_name:         r.device_name,
    vat_7_net_cents:     r.vat_7_net_cents,
    vat_7_tax_cents:     r.vat_7_tax_cents,
    vat_19_net_cents:    r.vat_19_net_cents,
    vat_19_tax_cents:    r.vat_19_tax_cents,
    total_gross_cents:   r.total_gross_cents,
    tip_cents:           r.tip_cents,
    is_takeaway:         r.is_takeaway,
    is_split_receipt:    r.is_split_receipt,
    tse_pending:         r.tse_pending === 1 || r.tse_pending === true,
    tse_transaction_id:  r.tse_transaction_id  ?? null,
    tse_serial_number:   r.tse_serial_number   ?? null,
    tse_signature:       r.tse_signature       ?? null,
    tse_counter:         r.tse_counter         ?? null,
    tse_transaction_start: r.tse_transaction_start ?? null,
    tse_transaction_end:   r.tse_transaction_end   ?? null,
    created_at:          r.created_at,
    raw_receipt_json:    rawJson,
    payments,
    receipt_data:        buildReceiptData(r, rawJson, payments),
  });
}

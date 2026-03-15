import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';

// ─── Plan-Limits: Rückblick in Tagen ─────────────────────────────────────────

const REPORT_DAYS_LIMIT: Record<string, number> = {
  starter:  30,
  pro:      365,
  business: 3650,
};

async function getPlanLimit(tenantId: number): Promise<{ maxDays: number; plan: string }> {
  const [rows] = await db.execute<any[]>('SELECT plan FROM tenants WHERE id = ?', [tenantId]);
  const plan = rows[0]?.plan ?? 'starter';
  return { maxDays: REPORT_DAYS_LIMIT[plan] ?? 30, plan };
}

function checkDateRangeAllowed(from: string, maxDays: number, plan: string, res: Response): boolean {
  const earliest = new Date();
  earliest.setDate(earliest.getDate() - maxDays);
  const earliestStr = earliest.toISOString().slice(0, 10);
  if (from < earliestStr) {
    res.status(403).json({
      error: `Plan-Limit: ${plan}-Plan erlaubt maximal ${maxDays} Tage Rückblick (frühestes Datum: ${earliestStr}).`,
    });
    return false;
  }
  return true;
}

// ─── Schemas ──────────────────────────────────────────────────────────────────

const dailySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
});

const summarySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
  to:   z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Format: YYYY-MM-DD'),
});

// ─── GET /reports/daily?date= ─────────────────────────────────────────────────

export async function getDailyReport(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const parsed = dailySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(422).json({ error: 'Validierungsfehler.', details: parsed.error.flatten().fieldErrors });
    return;
  }
  const { date } = parsed.data;

  const { maxDays, plan } = await getPlanLimit(tenantId);
  if (!checkDateRangeAllowed(date, maxDays, plan, res)) return;

  // MwSt + Gesamtumsatz aus Receipts
  const [receiptRows] = await db.execute<any[]>(
    `SELECT
       COUNT(*)                              AS receipt_count,
       COALESCE(SUM(vat_7_net_cents),   0)  AS vat_7_net_cents,
       COALESCE(SUM(vat_7_tax_cents),   0)  AS vat_7_tax_cents,
       COALESCE(SUM(vat_19_net_cents),  0)  AS vat_19_net_cents,
       COALESCE(SUM(vat_19_tax_cents),  0)  AS vat_19_tax_cents,
       COALESCE(SUM(total_gross_cents), 0)  AS total_gross_cents
     FROM receipts
     WHERE tenant_id = ? AND DATE(created_at) = ? AND status = 'active'`,
    [tenantId, date]
  );

  // Payments nach Zahlungsart
  const [paymentRows] = await db.execute<any[]>(
    `SELECT p.method, COALESCE(SUM(p.amount_cents), 0) AS total_cents
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE r.tenant_id = ? AND DATE(r.created_at) = ? AND r.status = 'active'
     GROUP BY p.method`,
    [tenantId, date]
  );

  // Stornos des Tages
  const [cancelRows] = await db.execute<any[]>(
    `SELECT COUNT(*) AS cancellation_count
     FROM cancellations c
     JOIN receipts r ON r.id = c.original_receipt_id
     WHERE r.tenant_id = ? AND DATE(c.created_at) = ?`,
    [tenantId, date]
  );

  // Sessions des Tages
  const [sessionRows] = await db.execute<any[]>(
    `SELECT id, opened_at, closed_at, opening_cash_cents, closing_cash_cents,
            expected_cash_cents, difference_cents, status
     FROM cash_register_sessions
     WHERE tenant_id = ? AND DATE(opened_at) = ?
     ORDER BY opened_at ASC`,
    [tenantId, date]
  );

  const r = receiptRows[0];
  const cashPayment = paymentRows.find((p: any) => p.method === 'cash');
  const cardPayment = paymentRows.find((p: any) => p.method === 'card');

  res.json({
    date,
    receipt_count:       Number(r.receipt_count),
    cancellation_count:  Number(cancelRows[0].cancellation_count),
    total_gross_cents:   Number(r.total_gross_cents),
    vat_7_net_cents:     Number(r.vat_7_net_cents),
    vat_7_tax_cents:     Number(r.vat_7_tax_cents),
    vat_19_net_cents:    Number(r.vat_19_net_cents),
    vat_19_tax_cents:    Number(r.vat_19_tax_cents),
    payments_cash_cents: Number(cashPayment?.total_cents ?? 0),
    payments_card_cents: Number(cardPayment?.total_cents ?? 0),
    sessions: sessionRows.map((s: any) => ({
      id:                  s.id,
      opened_at:           s.opened_at,
      closed_at:           s.closed_at   ?? null,
      opening_cash_cents:  s.opening_cash_cents,
      closing_cash_cents:  s.closing_cash_cents  ?? null,
      expected_cash_cents: s.expected_cash_cents ?? null,
      difference_cents:    s.difference_cents    ?? null,
      status:              s.status,
    })),
  });
}

// ─── GET /reports/summary?from=&to= ──────────────────────────────────────────

export async function getSummaryReport(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const parsed = summarySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(422).json({ error: 'Validierungsfehler.', details: parsed.error.flatten().fieldErrors });
    return;
  }
  const { from, to } = parsed.data;

  if (from > to) {
    res.status(422).json({ error: 'from darf nicht nach to liegen.' });
    return;
  }

  const { maxDays, plan } = await getPlanLimit(tenantId);
  if (!checkDateRangeAllowed(from, maxDays, plan, res)) return;

  // Gesamtsummen
  const [totalRows] = await db.execute<any[]>(
    `SELECT
       COUNT(*)                              AS receipt_count,
       COALESCE(SUM(vat_7_net_cents),   0)  AS vat_7_net_cents,
       COALESCE(SUM(vat_7_tax_cents),   0)  AS vat_7_tax_cents,
       COALESCE(SUM(vat_19_net_cents),  0)  AS vat_19_net_cents,
       COALESCE(SUM(vat_19_tax_cents),  0)  AS vat_19_tax_cents,
       COALESCE(SUM(total_gross_cents), 0)  AS total_gross_cents
     FROM receipts
     WHERE tenant_id = ? AND DATE(created_at) BETWEEN ? AND ? AND status = 'active'`,
    [tenantId, from, to]
  );

  // Gesamt-Payments nach Methode
  const [paymentTotals] = await db.execute<any[]>(
    `SELECT p.method, COALESCE(SUM(p.amount_cents), 0) AS total_cents
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE r.tenant_id = ? AND DATE(r.created_at) BETWEEN ? AND ? AND r.status = 'active'
     GROUP BY p.method`,
    [tenantId, from, to]
  );

  // Pro-Tag-Aufschlüsselung (Receipts)
  const [byDayRows] = await db.execute<any[]>(
    `SELECT
       DATE(created_at)                      AS date,
       COUNT(*)                              AS receipt_count,
       COALESCE(SUM(vat_7_net_cents),   0)  AS vat_7_net_cents,
       COALESCE(SUM(vat_7_tax_cents),   0)  AS vat_7_tax_cents,
       COALESCE(SUM(vat_19_net_cents),  0)  AS vat_19_net_cents,
       COALESCE(SUM(vat_19_tax_cents),  0)  AS vat_19_tax_cents,
       COALESCE(SUM(total_gross_cents), 0)  AS total_gross_cents
     FROM receipts
     WHERE tenant_id = ? AND DATE(created_at) BETWEEN ? AND ? AND status = 'active'
     GROUP BY DATE(created_at)
     ORDER BY date ASC`,
    [tenantId, from, to]
  );

  // Pro-Tag-Payments nach Methode
  const [byDayPayments] = await db.execute<any[]>(
    `SELECT
       DATE(r.created_at) AS date,
       p.method,
       COALESCE(SUM(p.amount_cents), 0) AS total_cents
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE r.tenant_id = ? AND DATE(r.created_at) BETWEEN ? AND ? AND r.status = 'active'
     GROUP BY DATE(r.created_at), p.method`,
    [tenantId, from, to]
  );

  const t = totalRows[0];
  const cashTotal = paymentTotals.find((p: any) => p.method === 'cash');
  const cardTotal = paymentTotals.find((p: any) => p.method === 'card');

  const byDay = byDayRows.map((row: any) => {
    const dateStr = row.date instanceof Date
      ? row.date.toISOString().slice(0, 10)
      : String(row.date);
    const dayPayments = byDayPayments.filter((p: any) => {
      const pDate = p.date instanceof Date ? p.date.toISOString().slice(0, 10) : String(p.date);
      return pDate === dateStr;
    });
    return {
      date:                dateStr,
      receipt_count:       Number(row.receipt_count),
      total_gross_cents:   Number(row.total_gross_cents),
      vat_7_net_cents:     Number(row.vat_7_net_cents),
      vat_7_tax_cents:     Number(row.vat_7_tax_cents),
      vat_19_net_cents:    Number(row.vat_19_net_cents),
      vat_19_tax_cents:    Number(row.vat_19_tax_cents),
      payments_cash_cents: Number(dayPayments.find((p: any) => p.method === 'cash')?.total_cents ?? 0),
      payments_card_cents: Number(dayPayments.find((p: any) => p.method === 'card')?.total_cents ?? 0),
    };
  });

  res.json({
    from,
    to,
    receipt_count:       Number(t.receipt_count),
    total_gross_cents:   Number(t.total_gross_cents),
    vat_7_net_cents:     Number(t.vat_7_net_cents),
    vat_7_tax_cents:     Number(t.vat_7_tax_cents),
    vat_19_net_cents:    Number(t.vat_19_net_cents),
    vat_19_tax_cents:    Number(t.vat_19_tax_cents),
    payments_cash_cents: Number(cashTotal?.total_cents ?? 0),
    payments_card_cents: Number(cardTotal?.total_cents ?? 0),
    by_day:              byDay,
  });
}

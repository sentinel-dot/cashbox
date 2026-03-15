import { Request, Response } from 'express';
import { z } from 'zod';
import { db, auditDb } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const openSessionSchema = z.object({
  opening_cash_cents: z.number().int().nonnegative(),
});

export const closeSessionSchema = z.object({
  closing_cash_cents: z.number().int().nonnegative(),
});

export const movementSchema = z.object({
  type:         z.enum(['deposit', 'withdrawal']),
  amount_cents: z.number().int().positive(),
  reason:       z.string().min(1).max(500),
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Berechnet den Z-Bericht-Snapshot für eine Session.
 * Wird bei session.close() generiert und unveränderlich in z_reports gespeichert.
 */
async function buildZReportData(sessionId: number, tenantId: number) {
  // Zahlungen der Session aggregiert nach Methode und MwSt-Satz
  const [payments] = await db.execute<any[]>(
    `SELECT
       p.method,
       SUM(p.amount_cents)  AS total_amount_cents,
       COUNT(DISTINCT p.order_id) AS order_count
     FROM payments p
     JOIN orders o ON o.id = p.order_id
     WHERE o.session_id = ? AND o.tenant_id = ?
     GROUP BY p.method`,
    [sessionId, tenantId]
  );

  // MwSt-Aufschlüsselung aus order_items
  const [vatRows] = await db.execute<any[]>(
    `SELECT
       oi.vat_rate,
       SUM(oi.subtotal_cents) AS net_plus_vat_cents
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE o.session_id = ? AND o.tenant_id = ? AND o.status = 'paid'
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)
     GROUP BY oi.vat_rate`,
    [sessionId, tenantId]
  );

  // Rabatte
  const [discountRow] = await db.execute<any[]>(
    `SELECT COALESCE(SUM(oi.discount_cents), 0) AS total_discount_cents
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE o.session_id = ? AND o.tenant_id = ? AND o.status = 'paid'
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`,
    [sessionId, tenantId]
  );

  // Stornos in dieser Session
  const [cancellationRow] = await db.execute<any[]>(
    `SELECT COUNT(*) AS cancellation_count
     FROM cancellations c
     JOIN receipts r ON r.id = c.original_receipt_id
     JOIN orders o ON o.id = r.order_id
     WHERE o.session_id = ? AND o.tenant_id = ?`,
    [sessionId, tenantId]
  );

  // Einlagen & Entnahmen
  const [movements] = await db.execute<any[]>(
    `SELECT type, SUM(amount_cents) AS total_cents
     FROM cash_movements
     WHERE session_id = ? AND tenant_id = ?
     GROUP BY type`,
    [sessionId, tenantId]
  );

  // Gesamtumsatz
  const totalRevenue = payments.reduce((s: number, p: any) => s + Number(p.total_amount_cents), 0);
  const totalOrders  = payments.reduce((s: number, p: any) => s + Number(p.order_count), 0);

  return {
    payments:           payments.map(p => ({ method: p.method, total_amount_cents: Number(p.total_amount_cents), order_count: Number(p.order_count) })),
    vat_breakdown:      vatRows.map(v => ({ vat_rate: v.vat_rate, net_plus_vat_cents: Number(v.net_plus_vat_cents) })),
    total_revenue_cents: totalRevenue,
    total_orders:        totalOrders,
    total_discount_cents: Number(discountRow[0]?.total_discount_cents ?? 0),
    cancellation_count:   Number(cancellationRow[0]?.cancellation_count ?? 0),
    movements:            movements.map(m => ({ type: m.type, total_cents: Number(m.total_cents) })),
  };
}

// ─── Handlers ─────────────────────────────────────────────────────────────────

export async function openSession(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const deviceId  = req.auth!.deviceId;
  const userId    = req.auth!.userId;
  const { opening_cash_cents } = req.body as z.infer<typeof openSessionSchema>;

  // Nur eine offene Session pro Gerät erlaubt
  const [existing] = await db.execute<any[]>(
    `SELECT id FROM cash_register_sessions
     WHERE tenant_id = ? AND device_id = ? AND status = 'open' LIMIT 1`,
    [tenantId, deviceId]
  );
  if (existing.length > 0) {
    res.status(409).json({ error: 'Es gibt bereits eine offene Kassensitzung für dieses Gerät.' });
    return;
  }

  const [result] = await db.execute<any>(
    `INSERT INTO cash_register_sessions
       (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
     VALUES (?, ?, ?, ?, 'open')`,
    [tenantId, deviceId, userId, opening_cash_cents]
  );
  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId, action: 'session.opened',
    entityType: 'cash_register_session', entityId: newId,
    diff: { new: { opening_cash_cents } },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({ id: newId, opening_cash_cents, status: 'open' });
}

export async function getCurrentSession(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const deviceId = req.auth!.deviceId;

  const [rows] = await db.execute<any[]>(
    `SELECT s.id, s.opening_cash_cents, s.opened_at, s.status,
            u.name AS opened_by_name
     FROM cash_register_sessions s
     JOIN users u ON u.id = s.opened_by_user_id
     WHERE s.tenant_id = ? AND s.device_id = ? AND s.status = 'open'
     LIMIT 1`,
    [tenantId, deviceId]
  );

  if (rows.length === 0) {
    res.status(404).json({ error: 'Keine offene Kassensitzung.' });
    return;
  }

  const session = rows[0];

  // Bewegungen der laufenden Session
  const [movements] = await db.execute<any[]>(
    `SELECT type, amount_cents, reason, created_at FROM cash_movements
     WHERE session_id = ? AND tenant_id = ?
     ORDER BY created_at ASC`,
    [session.id, tenantId]
  );

  res.json({ ...session, movements });
}

export async function closeSession(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const deviceId = req.auth!.deviceId;
  const userId   = req.auth!.userId;
  const { closing_cash_cents } = req.body as z.infer<typeof closeSessionSchema>;

  // Offene Session holen
  const [rows] = await db.execute<any[]>(
    `SELECT id, opening_cash_cents FROM cash_register_sessions
     WHERE tenant_id = ? AND device_id = ? AND status = 'open' LIMIT 1`,
    [tenantId, deviceId]
  );
  if (rows.length === 0) {
    res.status(404).json({ error: 'Keine offene Kassensitzung.' });
    return;
  }
  const session   = rows[0];
  const sessionId = session.id as number;

  // Offene Orders blockieren Abschluss
  const [openOrders] = await db.execute<any[]>(
    `SELECT COUNT(*) AS cnt FROM orders
     WHERE session_id = ? AND tenant_id = ? AND status = 'open'`,
    [sessionId, tenantId]
  );
  if (Number(openOrders[0].cnt) > 0) {
    res.status(409).json({
      error: `Es gibt noch ${openOrders[0].cnt} offene Bestellung(en). Bitte zuerst abschließen oder stornieren.`,
    });
    return;
  }

  // Einnahmen aus Zahlungen
  const [revenueRow] = await db.execute<any[]>(
    `SELECT COALESCE(SUM(p.amount_cents), 0) AS cash_revenue_cents
     FROM payments p
     JOIN orders o ON o.id = p.order_id
     WHERE o.session_id = ? AND o.tenant_id = ? AND p.method = 'cash'`,
    [sessionId, tenantId]
  );

  // Einlagen & Entnahmen
  const [movementRows] = await db.execute<any[]>(
    `SELECT type, COALESCE(SUM(amount_cents), 0) AS total_cents
     FROM cash_movements WHERE session_id = ? AND tenant_id = ? GROUP BY type`,
    [sessionId, tenantId]
  );
  const deposits    = Number(movementRows.find((m: any) => m.type === 'deposit')?.total_cents  ?? 0);
  const withdrawals = Number(movementRows.find((m: any) => m.type === 'withdrawal')?.total_cents ?? 0);

  const cashRevenue       = Number(revenueRow[0].cash_revenue_cents);
  const expected_cash_cents = session.opening_cash_cents + cashRevenue + deposits - withdrawals;
  const difference_cents    = closing_cash_cents - expected_cash_cents;

  // Z-Bericht-Daten aggregieren
  const reportData = await buildZReportData(sessionId, tenantId);

  // Session schließen (UPDATE erlaubt auf cash_register_sessions — kein Finanzdatum)
  await db.execute(
    `UPDATE cash_register_sessions
     SET status = 'closed', closed_by_user_id = ?, closed_at = NOW(),
         closing_cash_cents = ?, expected_cash_cents = ?, difference_cents = ?
     WHERE id = ? AND tenant_id = ?`,
    [userId, closing_cash_cents, expected_cash_cents, difference_cents, sessionId, tenantId]
  );

  // Z-Bericht unveränderlich speichern (audit_insert_user = INSERT-only)
  const zReportJson = {
    session_id:            sessionId,
    tenant_id:             tenantId,
    closed_at:             new Date().toISOString(),
    opening_cash_cents:    session.opening_cash_cents,
    closing_cash_cents,
    expected_cash_cents,
    difference_cents,
    ...reportData,
  };
  const [zResult] = await auditDb.execute<any>(
    `INSERT INTO z_reports (session_id, tenant_id, report_json) VALUES (?, ?, ?)`,
    [sessionId, tenantId, JSON.stringify(zReportJson)]
  );

  await writeAuditLog({
    tenantId, userId, action: 'session.closed',
    entityType: 'cash_register_session', entityId: sessionId,
    diff: { new: { closing_cash_cents, expected_cash_cents, difference_cents } },
    ipAddress: req.ip, deviceId,
  });

  res.json({
    session_id:            sessionId,
    z_report_id:           zResult.insertId,
    closing_cash_cents,
    expected_cash_cents,
    difference_cents,
    ...reportData,
  });
}

export async function getSession(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const targetId  = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Session-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    `SELECT s.id, s.status, s.opening_cash_cents, s.closing_cash_cents,
            s.expected_cash_cents, s.difference_cents,
            s.opened_at, s.closed_at,
            u1.name AS opened_by_name,
            u2.name AS closed_by_name
     FROM cash_register_sessions s
     JOIN users u1 ON u1.id = s.opened_by_user_id
     LEFT JOIN users u2 ON u2.id = s.closed_by_user_id
     WHERE s.id = ? AND s.tenant_id = ?`,
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Kassensitzung nicht gefunden.' }); return; }

  const [movements] = await db.execute<any[]>(
    `SELECT type, amount_cents, reason, created_at FROM cash_movements
     WHERE session_id = ? AND tenant_id = ? ORDER BY created_at ASC`,
    [targetId, tenantId]
  );

  res.json({ ...rows[0], movements });
}

export async function getZReport(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Session-ID.' });
    return;
  }

  // Sicherstellen dass Session zum Tenant gehört
  const [sessionRows] = await db.execute<any[]>(
    `SELECT id, status FROM cash_register_sessions WHERE id = ? AND tenant_id = ?`,
    [targetId, tenantId]
  );
  if (sessionRows.length === 0) { res.status(404).json({ error: 'Kassensitzung nicht gefunden.' }); return; }
  if (sessionRows[0].status !== 'closed') {
    res.status(409).json({ error: 'Z-Bericht ist erst nach Sitzungsabschluss verfügbar.' });
    return;
  }

  const [reportRows] = await db.execute<any[]>(
    `SELECT id, report_json, created_at FROM z_reports
     WHERE session_id = ? AND tenant_id = ? LIMIT 1`,
    [targetId, tenantId]
  );
  if (reportRows.length === 0) { res.status(404).json({ error: 'Z-Bericht nicht gefunden.' }); return; }

  const reportJson = typeof reportRows[0].report_json === 'string'
    ? JSON.parse(reportRows[0].report_json)
    : reportRows[0].report_json;

  res.json({
    id:         reportRows[0].id,
    created_at: reportRows[0].created_at,
    report:     reportJson,
  });
}

export async function addMovement(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const deviceId = req.auth!.deviceId;
  const userId   = req.auth!.userId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Session-ID.' });
    return;
  }

  const { type, amount_cents, reason } = req.body as z.infer<typeof movementSchema>;

  // Session muss offen und zum Tenant+Gerät gehören
  const [rows] = await db.execute<any[]>(
    `SELECT id FROM cash_register_sessions
     WHERE id = ? AND tenant_id = ? AND device_id = ? AND status = 'open'`,
    [targetId, tenantId, deviceId]
  );
  if (rows.length === 0) {
    res.status(404).json({ error: 'Offene Kassensitzung nicht gefunden.' });
    return;
  }

  const [result] = await db.execute<any>(
    `INSERT INTO cash_movements (session_id, tenant_id, type, amount_cents, reason, created_by_user_id)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [targetId, tenantId, type, amount_cents, reason, userId]
  );

  await writeAuditLog({
    tenantId, userId, action: `movement.${type}`,
    entityType: 'cash_movement', entityId: result.insertId,
    diff: { new: { type, amount_cents, reason } },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({ id: result.insertId, type, amount_cents, reason });
}

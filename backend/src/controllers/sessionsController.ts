import { Request, Response } from 'express';
import { z } from 'zod';
import type { Pool, PoolConnection } from 'mysql2/promise';
import { db, auditDb } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { logger } from '../logger.js';

// db-Pool oder TX-Connection — buildZReportData läuft beim Schließen innerhalb
// der closeSession-TX (unter Session-Lock), damit keine parallele Zahlung
// zwischen Aggregation und Schließen committen kann
type SqlExecutor = Pool | PoolConnection;

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
async function buildZReportData(sessionId: number, tenantId: number, exec: SqlExecutor = db) {
  // Zahlungen der Session aggregiert nach Methode.
  // Join über receipts.session_id (nicht orders.session_id): ein Storno am Folgetag
  // gehört in die Kassenlade der Session, in der er durchgeführt wurde.
  // Negative Storno-payments netten automatisch aus.
  const [payments] = await exec.execute<any[]>(
    `SELECT
       p.method,
       SUM(p.amount_cents)  AS total_amount_cents,
       COUNT(DISTINCT p.order_id) AS order_count
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE r.session_id = ? AND r.tenant_id = ? AND r.status = 'active'
     GROUP BY p.method`,
    [sessionId, tenantId]
  );

  // Bezahlte Bestellungen der Session (DISTINCT über alle Methoden —
  // Mixed-Payment-Orders sonst doppelt gezählt)
  const [orderCountRow] = await exec.execute<any[]>(
    `SELECT COUNT(DISTINCT p.order_id) AS total_orders
     FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE r.session_id = ? AND r.tenant_id = ? AND r.status = 'active'
       AND p.amount_cents > 0`,
    [sessionId, tenantId]
  );

  // MwSt-Aufschlüsselung aus receipts (Storno-Bons mit negativen Beträgen netten aus)
  const [vatRows] = await exec.execute<any[]>(
    `SELECT
       COALESCE(SUM(vat_7_net_cents  + vat_7_tax_cents),  0) AS vat_7_gross_cents,
       COALESCE(SUM(vat_19_net_cents + vat_19_tax_cents), 0) AS vat_19_gross_cents
     FROM receipts
     WHERE session_id = ? AND tenant_id = ? AND status = 'active'`,
    [sessionId, tenantId]
  );

  // Rabatte
  const [discountRow] = await exec.execute<any[]>(
    `SELECT COALESCE(SUM(oi.discount_cents), 0) AS total_discount_cents
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE o.session_id = ? AND o.tenant_id = ? AND o.status = 'paid'
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`,
    [sessionId, tenantId]
  );

  // Stornos in dieser Session — zählt über die Session des STORNO-Bons
  // (cancellation_receipt_id), nicht der Original-Order: ein Storno am Folgetag
  // nettet die Beträge in der Session, in der er durchgeführt wurde, und muss
  // dort auch gezählt werden (die Original-Session ist längst geschlossen).
  const [cancellationRow] = await exec.execute<any[]>(
    `SELECT COUNT(*) AS cancellation_count
     FROM cancellations c
     JOIN receipts cr ON cr.id = c.cancellation_receipt_id
     WHERE cr.session_id = ? AND cr.tenant_id = ?`,
    [sessionId, tenantId]
  );

  // Einlagen & Entnahmen
  const [movements] = await exec.execute<any[]>(
    `SELECT type, SUM(amount_cents) AS total_cents
     FROM cash_movements
     WHERE session_id = ? AND tenant_id = ?
     GROUP BY type`,
    [sessionId, tenantId]
  );

  // Gesamtumsatz (Storno-payments negativ → nettet automatisch)
  const totalRevenue = payments.reduce((s: number, p: any) => s + Number(p.total_amount_cents), 0);
  const totalOrders  = Number(orderCountRow[0]?.total_orders ?? 0);

  // vat_breakdown-Shape beibehalten (iOS/Tests): ein Eintrag je Steuersatz
  const vat7Gross  = Number(vatRows[0]?.vat_7_gross_cents  ?? 0);
  const vat19Gross = Number(vatRows[0]?.vat_19_gross_cents ?? 0);
  const vatBreakdown: Array<{ vat_rate: string; net_plus_vat_cents: number }> = [];
  if (vat7Gross  !== 0) vatBreakdown.push({ vat_rate: '7',  net_plus_vat_cents: vat7Gross });
  if (vat19Gross !== 0) vatBreakdown.push({ vat_rate: '19', net_plus_vat_cents: vat19Gross });

  return {
    payments:           payments.map(p => ({ method: p.method, total_amount_cents: Number(p.total_amount_cents), order_count: Number(p.order_count) })),
    vat_breakdown:      vatBreakdown,
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

  // Nur eine offene Session pro Gerät — Check+Insert in TX mit Lock auf der
  // Geräte-Zeile, sonst öffnen zwei parallele Requests zwei Sessions
  const conn = await db.getConnection();
  let newId!: number;
  try {
    await conn.beginTransaction();
    await conn.execute(
      `SELECT id FROM devices WHERE id = ? AND tenant_id = ? FOR UPDATE`,
      [deviceId, tenantId]
    );
    const [existing] = await conn.execute<any[]>(
      `SELECT id FROM cash_register_sessions
       WHERE tenant_id = ? AND device_id = ? AND status = 'open' LIMIT 1`,
      [tenantId, deviceId]
    );
    if (existing.length > 0) {
      await conn.rollback();
      res.status(409).json({ error: 'Es gibt bereits eine offene Kassensitzung für dieses Gerät.' });
      return;
    }

    const [result] = await conn.execute<any>(
      `INSERT INTO cash_register_sessions
         (tenant_id, device_id, opened_by_user_id, opening_cash_cents, status)
       VALUES (?, ?, ?, ?, 'open')`,
      [tenantId, deviceId, userId, opening_cash_cents]
    );
    newId = result.insertId as number;
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

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

  // Alles unter Session-Lock in EINER TX: payOrder/splitBill/cancelReceipt sperren
  // dieselbe Session-Zeile — eine Zahlung, die beim Schließen noch läuft, committet
  // entweder VOR der Aggregation oder bekommt 409. Ohne den Lock kann ein Bon
  // zwischen Aggregation und Schließen committen und fehlt im unveränderlichen
  // Z-Bericht → unkorrigierbare Kassendifferenz.
  const conn = await db.getConnection();
  let sessionId!: number;
  let opening_cash_cents!: number;
  let expected_cash_cents!: number;
  let difference_cents!: number;
  let reportData!: Awaited<ReturnType<typeof buildZReportData>>;

  try {
    await conn.beginTransaction();

    // Offene Session sperren (serialisiert gegen Zahlungen + parallele close-Requests)
    const [rows] = await conn.execute<any[]>(
      `SELECT id, opening_cash_cents FROM cash_register_sessions
       WHERE tenant_id = ? AND device_id = ? AND status = 'open' LIMIT 1 FOR UPDATE`,
      [tenantId, deviceId]
    );
    if (rows.length === 0) {
      await conn.rollback();
      res.status(404).json({ error: 'Keine offene Kassensitzung.' });
      return;
    }
    const session = rows[0];
    sessionId = session.id as number;
    opening_cash_cents = session.opening_cash_cents as number;

    // Offene Orders blockieren Abschluss
    const [openOrders] = await conn.execute<any[]>(
      `SELECT COUNT(*) AS cnt FROM orders
       WHERE session_id = ? AND tenant_id = ? AND status = 'open'`,
      [sessionId, tenantId]
    );
    if (Number(openOrders[0].cnt) > 0) {
      await conn.rollback();
      res.status(409).json({
        error: `Es gibt noch ${openOrders[0].cnt} offene Bestellung(en). Bitte zuerst abschließen oder stornieren.`,
      });
      return;
    }

    // Bar-Einnahmen der Session — via receipts.session_id (Storno in dieser Session
    // erzeugt negative payments und reduziert den erwarteten Kassenbestand)
    const [revenueRow] = await conn.execute<any[]>(
      `SELECT COALESCE(SUM(p.amount_cents), 0) AS cash_revenue_cents
       FROM payments p
       JOIN receipts r ON r.id = p.receipt_id
       WHERE r.session_id = ? AND r.tenant_id = ? AND r.status = 'active' AND p.method = 'cash'`,
      [sessionId, tenantId]
    );

    // Einlagen & Entnahmen
    const [movementRows] = await conn.execute<any[]>(
      `SELECT type, COALESCE(SUM(amount_cents), 0) AS total_cents
       FROM cash_movements WHERE session_id = ? AND tenant_id = ? GROUP BY type`,
      [sessionId, tenantId]
    );
    const deposits    = Number(movementRows.find((m: any) => m.type === 'deposit')?.total_cents  ?? 0);
    const withdrawals = Number(movementRows.find((m: any) => m.type === 'withdrawal')?.total_cents ?? 0);

    const cashRevenue     = Number(revenueRow[0].cash_revenue_cents);
    expected_cash_cents   = session.opening_cash_cents + cashRevenue + deposits - withdrawals;
    difference_cents      = closing_cash_cents - expected_cash_cents;

    // Z-Bericht-Daten aggregieren — unter dem Session-Lock (gleiche TX)
    reportData = await buildZReportData(sessionId, tenantId, conn);

    // Session schließen — status='open'-Guard bleibt als Belt-and-Suspenders
    const [closeResult] = await conn.execute<any>(
      `UPDATE cash_register_sessions
       SET status = 'closed', closed_by_user_id = ?, closed_at = NOW(),
           closing_cash_cents = ?, expected_cash_cents = ?, difference_cents = ?
       WHERE id = ? AND tenant_id = ? AND status = 'open'`,
      [userId, closing_cash_cents, expected_cash_cents, difference_cents, sessionId, tenantId]
    );
    if (closeResult.affectedRows !== 1) {
      await conn.rollback();
      res.status(409).json({ error: 'Kassensitzung wurde bereits geschlossen.' });
      return;
    }

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  // Z-Bericht unveränderlich speichern (audit_insert_user = INSERT-only).
  // Läuft nach dem Commit (anderer DB-User/Pool — keine gemeinsame TX möglich):
  // schlägt der INSERT fehl, ist die Session geschlossen OHNE Z-Bericht — laut
  // loggen, damit das nachgeholt werden kann (Daten sind rekonstruierbar).
  const zReportJson = {
    session_id:            sessionId,
    tenant_id:             tenantId,
    closed_at:             new Date().toISOString(),
    opening_cash_cents,
    closing_cash_cents,
    expected_cash_cents,
    difference_cents,
    ...reportData,
  };
  let zResult: any;
  try {
    [zResult] = await auditDb.execute<any>(
      `INSERT INTO z_reports (session_id, tenant_id, report_json) VALUES (?, ?, ?)`,
      [sessionId, tenantId, JSON.stringify(zReportJson)]
    );
  } catch (err) {
    logger.error(
      { err, tenant: tenantId, session: sessionId, z_report: zReportJson },
      'z_reports-INSERT fehlgeschlagen — Session ist geschlossen OHNE Z-Bericht'
    );
    throw err;
  }

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

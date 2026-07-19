import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { nextReceiptNumber } from '../services/sequences.js';
import { processTseTransaction } from '../services/fiskaly.js';

// ─── Schema ───────────────────────────────────────────────────────────────────

export const cancelReceiptSchema = z.object({
  reason: z.string().min(1).max(500),
});

// ─── Gegenbuchungs-Werte (pure, unit-getestet) ───────────────────────────────
// REQ-GOBD-004: Storno-Bon trägt negierte Beträge + negative payments je
// Original-Zahlungsmittel — eine Quelle für JSON-Snapshot UND INSERT-Parameter,
// damit beide nicht auseinanderdriften können.

export type CancellationAmounts = {
  vat_7_net_cents: number;
  vat_7_tax_cents: number;
  vat_19_net_cents: number;
  vat_19_tax_cents: number;
  total_gross_cents: number;
};

export type PaymentLine = { method: 'cash' | 'card'; amount_cents: number };

export function buildCancellationValues(
  original: CancellationAmounts,
  originalPayments: PaymentLine[]
): {
  negatedAmounts: CancellationAmounts;
  tsePayments: PaymentLine[];       // positiv — für TSE-CANCELLATION-Transaktion
  negatedPayments: PaymentLine[];   // negativ — für payments-INSERTs
} {
  // Fallback: Alt-Bons ohne payments-Zeilen → eine cash-Zeile über den Gesamtbetrag
  const tsePayments = originalPayments.length > 0
    ? originalPayments.map(p => ({ method: p.method, amount_cents: p.amount_cents }))
    : [{ method: 'cash' as const, amount_cents: original.total_gross_cents }];

  return {
    negatedAmounts: {
      vat_7_net_cents:   -original.vat_7_net_cents,
      vat_7_tax_cents:   -original.vat_7_tax_cents,
      vat_19_net_cents:  -original.vat_19_net_cents,
      vat_19_tax_cents:  -original.vat_19_tax_cents,
      total_gross_cents: -original.total_gross_cents,
    },
    tsePayments,
    negatedPayments: tsePayments.map(p => ({ method: p.method, amount_cents: -p.amount_cents })),
  };
}

// ─── POST /receipts/:id/cancel ────────────────────────────────────────────────

export async function cancelReceipt(req: Request, res: Response): Promise<void> {
  const tenantId   = req.auth!.tenantId;
  const userId     = req.auth!.userId;
  const deviceId   = req.auth!.deviceId;
  const sessionId  = req.sessionId!;
  const receiptId  = Number(req.params['id']);
  const { reason } = req.body as z.infer<typeof cancelReceiptSchema>;

  if (!Number.isInteger(receiptId) || receiptId <= 0) {
    res.status(400).json({ error: 'Ungültige Receipt-ID.' });
    return;
  }

  // Rolle prüfen: nur owner/manager dürfen stornieren
  if (!['owner', 'manager'].includes(req.auth!.role)) {
    res.status(403).json({ error: 'Nur Owner oder Manager dürfen Bons stornieren.' });
    return;
  }

  // Original-Bon laden (Tenant-Isolation)
  const [receiptRows] = await db.execute<any[]>(
    `SELECT r.id, r.receipt_number, r.status, r.order_id, r.session_id,
            r.device_id, r.device_name,
            r.vat_7_net_cents, r.vat_7_tax_cents,
            r.vat_19_net_cents, r.vat_19_tax_cents,
            r.total_gross_cents, r.is_takeaway, r.raw_receipt_json
     FROM receipts r
     WHERE r.id = ? AND r.tenant_id = ?`,
    [receiptId, tenantId]
  );
  if (receiptRows.length === 0) {
    res.status(404).json({ error: 'Bon nicht gefunden.' });
    return;
  }

  const original = receiptRows[0];
  if (original.status !== 'active') {
    res.status(409).json({ error: 'Nur aktive Bons können storniert werden.' });
    return;
  }

  // Storno-von-Storno verhindern — die Gegenbuchung einer Gegenbuchung würde
  // den Umsatz wieder positiv buchen
  const originalJsonCheck = original.raw_receipt_json
    ? (typeof original.raw_receipt_json === 'string'
        ? JSON.parse(original.raw_receipt_json)
        : original.raw_receipt_json)
    : null;
  if (originalJsonCheck?.cancellation === true) {
    res.status(409).json({ error: 'Storno-Bons können nicht storniert werden.' });
    return;
  }

  // Prüfen ob Bon bereits storniert wurde (GoBD: kein Doppel-Storno)
  const [existingCancel] = await db.execute<any[]>(
    `SELECT c.id FROM cancellations c
     JOIN receipts r ON r.id = c.original_receipt_id
     WHERE c.original_receipt_id = ? AND r.tenant_id = ?`,
    [receiptId, tenantId]
  );
  if (existingCancel.length > 0) {
    res.status(409).json({ error: 'Dieser Bon wurde bereits storniert.' });
    return;
  }

  // Tenant + Device-Snapshots für Storno-Bon
  const [tenantRows] = await db.execute<any[]>(
    'SELECT name, address, vat_id, tax_number, fiskaly_tss_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  const [deviceRows] = await db.execute<any[]>(
    'SELECT id, name, tse_client_id FROM devices WHERE id = ? AND tenant_id = ?',
    [deviceId, tenantId]
  );
  if (deviceRows.length === 0) {
    res.status(500).json({ error: 'Gerät nicht gefunden.' });
    return;
  }

  const tenant = tenantRows[0];
  const device = deviceRows[0];

  // Original raw_receipt_json (bereits oben geparst) — für Storno-Bon-Snapshot
  const originalJson = originalJsonCheck;

  // Brutto-Beträge für TSE rekonstruieren (net + tax = gross)
  const vat7GrossCents  = (original.vat_7_net_cents  ?? 0) + (original.vat_7_tax_cents  ?? 0);
  const vat19GrossCents = (original.vat_19_net_cents ?? 0) + (original.vat_19_tax_cents ?? 0);

  // Original-Zahlungsmittel für TSE-CANCELLATION laden
  const [originalPayments] = await db.execute<any[]>(
    `SELECT p.method, p.amount_cents FROM payments p
     JOIN receipts r ON r.id = p.receipt_id
     WHERE p.receipt_id = ? AND r.tenant_id = ?`,
    [receiptId, tenantId]
  );
  const { negatedAmounts, tsePayments, negatedPayments } = buildCancellationValues(
    original,
    originalPayments.map((p: any) => ({ method: p.method as 'cash' | 'card', amount_cents: p.amount_cents }))
  );

  // ─── Fiskaly TSE-Storno-Transaktion (vor DB-TX) ───────────────────────────
  const tseResult = await processTseTransaction({
    tenantId, deviceId, orderId: original.order_id, userId,
    tssId:           tenant.fiskaly_tss_id ?? '',
    clientId:        device.tse_client_id  ?? '',
    vat7GrossCents,
    vat19GrossCents,
    payments:        tsePayments,
    receiptType:     'CANCELLATION',
  });

  // ─── DB-Transaktion ───────────────────────────────────────────────────────
  const conn = await db.getConnection();
  let cancellationReceiptId: number;
  let cancellationReceiptNumber: number | null = null;  // null bis vergeben — für Voided-Receipt-Fallback

  try {
    await conn.beginTransaction();

    // Original-Bon sperren — serialisiert parallele Storno-Requests (Doppel-Tap).
    // Die Vor-Prüfungen oben laufen ohne Lock und können beide passieren;
    // maßgeblich ist der Zustand NACH dem Lock.
    const [lockedReceipt] = await conn.execute<any[]>(
      `SELECT id, status FROM receipts WHERE id = ? AND tenant_id = ? FOR UPDATE`,
      [receiptId, tenantId]
    );
    if (lockedReceipt.length === 0 || lockedReceipt[0].status !== 'active') {
      await conn.rollback();
      res.status(409).json({ error: 'Nur aktive Bons können storniert werden.' });
      return;
    }

    // Doppel-Storno-Check erneut unter Lock (UNIQUE-Constraint uq_cancellations_original
    // ist der DB-Backstop, dieser Check liefert das saubere 409)
    const [cancelUnderLock] = await conn.execute<any[]>(
      `SELECT id FROM cancellations WHERE original_receipt_id = ? LIMIT 1`,
      [receiptId]
    );
    if (cancelUnderLock.length > 0) {
      await conn.rollback();
      res.status(409).json({ error: 'Dieser Bon wurde bereits storniert.' });
      return;
    }

    // Session muss noch offen sein — sonst landet die Gegenbuchung in einer
    // geschlossenen Session und fehlt im unveränderlichen Z-Bericht
    const [lockedSession] = await conn.execute<any[]>(
      `SELECT status FROM cash_register_sessions WHERE id = ? AND tenant_id = ? FOR UPDATE`,
      [sessionId, tenantId]
    );
    if (lockedSession.length === 0 || lockedSession[0].status !== 'open') {
      await conn.rollback();
      res.status(409).json({ error: 'Kassensitzung wurde zwischenzeitlich geschlossen. Bitte neue Sitzung öffnen.' });
      return;
    }

    // Storno-Bon-Nummer atomar vergeben
    cancellationReceiptNumber = await nextReceiptNumber(tenantId, conn);

    // raw_receipt_json des Storno-Bons — unveränderlicher Snapshot
    const now = new Date().toISOString();
    const cancellationJson = {
      receipt_number:           cancellationReceiptNumber,
      cancellation:             true,
      original_receipt_number:  original.receipt_number,
      original_receipt_id:      receiptId,
      reason,
      created_at:               now,
      tenant: {
        name:       tenant.name,
        address:    tenant.address,
        vat_id:     tenant.vat_id     ?? null,
        tax_number: tenant.tax_number ?? null,
      },
      device:     { id: device.id, name: device.name },
      items:      originalJson?.items ?? [],
      // Gegenbuchung: Beträge negiert — SUM()-Aggregationen (Berichte, Z-Bericht,
      // Kassenbestand) netten Original + Storno automatisch auf 0.
      // Items bleiben der positive Original-Snapshot (Dokumentation was storniert wurde).
      ...negatedAmounts,
      tse_pending:       tseResult.pending,
      tse_transaction_id: tseResult.tseTransactionId ?? null,
    };

    // Storno-Bon INSERT (GoBD: NUR INSERT, einmalig mit finalen TSE-Daten)
    const [cancelReceiptResult] = await conn.execute<any>(
      `INSERT INTO receipts
         (tenant_id, order_id, session_id, receipt_number, status,
          device_id, device_name,
          vat_7_net_cents, vat_7_tax_cents, vat_19_net_cents, vat_19_tax_cents,
          total_gross_cents, tip_cents, is_takeaway,
          tse_pending, tse_transaction_id, tse_serial_number, tse_signature,
          tse_counter, tse_transaction_start, tse_transaction_end,
          raw_receipt_json)
       VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        tenantId, original.order_id, sessionId, cancellationReceiptNumber,
        device.id, device.name,
        negatedAmounts.vat_7_net_cents,  negatedAmounts.vat_7_tax_cents,
        negatedAmounts.vat_19_net_cents, negatedAmounts.vat_19_tax_cents,
        negatedAmounts.total_gross_cents, original.is_takeaway,
        tseResult.pending ? 1 : 0,
        tseResult.tseTransactionId    ?? null,
        tseResult.tseSerialNumber     ?? null,
        tseResult.tseSignature        ?? null,
        tseResult.tseCounter          ?? null,
        tseResult.tseTransactionStart ?? null,
        tseResult.tseTransactionEnd   ?? null,
        JSON.stringify(cancellationJson),
      ]
    );
    cancellationReceiptId = cancelReceiptResult.insertId as number;

    // cancellations INSERT (GoBD: Gegenbuchung, NUR INSERT)
    await conn.execute(
      `INSERT INTO cancellations
         (original_receipt_id, original_receipt_number, cancellation_receipt_id, cancelled_by_user_id, reason)
       VALUES (?, ?, ?, ?, ?)`,
      [receiptId, original.receipt_number, cancellationReceiptId, userId, reason]
    );

    // Negative payments-Zeilen (Rückerstattung je Original-Zahlungsmittel) —
    // damit netten Kassenbestand (cash) und Zahlungsart-Summen automatisch aus.
    for (const p of negatedPayments) {
      await conn.execute(
        `INSERT INTO payments (order_id, receipt_id, method, amount_cents, tip_cents, paid_by_user_id)
         VALUES (?, ?, ?, ?, 0, ?)`,
        [original.order_id, cancellationReceiptId, p.method, p.amount_cents, userId]
      );
    }

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    // GoBD: Bon-Nummer vergeben → TX fehlgeschlagen → Voided-Receipt anlegen (best-effort)
    if (cancellationReceiptNumber !== null) {
      const voidConn = await db.getConnection().catch(() => null);
      if (voidConn) {
        try {
          await voidConn.beginTransaction();
          const voidNum = await nextReceiptNumber(tenantId, voidConn);
          await voidConn.execute(
            `INSERT INTO receipts
               (tenant_id, order_id, session_id, receipt_number, status,
                device_id, device_name, vat_7_net_cents, vat_7_tax_cents,
                vat_19_net_cents, vat_19_tax_cents, total_gross_cents, tip_cents,
                is_takeaway, tse_pending)
             VALUES (?, ?, ?, ?, 'voided', ?, ?, 0, 0, 0, 0, 0, 0, FALSE, 0)`,
            [tenantId, original.order_id, sessionId, voidNum, device.id, device.name]
          );
          await voidConn.commit();
        } catch { await voidConn.rollback().catch(() => {}); }
        finally { voidConn.release(); }
      }
    }
    throw err;
  } finally {
    conn.release();
  }

  // Audit-Log außerhalb TX (nicht-fatal)
  await writeAuditLog({
    tenantId, userId, action: 'receipt.cancelled',
    entityType: 'receipt', entityId: cancellationReceiptId!,
    diff: {
      new: {
        original_receipt_id:     receiptId,
        original_receipt_number: original.receipt_number,
        cancellation_receipt_id: cancellationReceiptId!,
        reason,
      },
    },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({
    cancellation_receipt_id:     cancellationReceiptId!,
    cancellation_receipt_number: cancellationReceiptNumber!,
    original_receipt_id:         receiptId,
    original_receipt_number:     original.receipt_number,
    // Betrag des Storno-Bons (Gegenbuchung) — negativ
    total_gross_cents:            -original.total_gross_cents,
    tse_pending:                  tseResult.pending,
    tse_transaction_id:           tseResult.tseTransactionId  ?? null,
  });
}

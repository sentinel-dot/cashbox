import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { nextReceiptNumber } from '../services/sequences.js';
import { processTseTransaction } from '../services/fiskaly.js';

// ─── Schemas ─────────────────────────────────────────────────────────────────

const paymentItemSchema = z.object({
  method:       z.enum(['cash', 'card']),
  amount_cents: z.number().int().positive(),
});

// Unterstützt beide Formate — wird intern zu { payments: [...] } normalisiert:
//   Einzel: { method: 'cash', amount_cents: 2500 }
//   Multi:  { payments: [{ method: 'cash', amount_cents: 1000 }, { method: 'card', amount_cents: 1500 }] }
export const payOrderSchema = z.union([
  z.object({ payments: z.array(paymentItemSchema).min(1) }),
  paymentItemSchema,
]).transform((data): { payments: Array<{ method: 'cash' | 'card'; amount_cents: number }> } => {
  if ('payments' in data) return { payments: data.payments };
  return { payments: [data as { method: 'cash' | 'card'; amount_cents: number }] };
});

// ─── MwSt-Berechnung (§ 14 UStG) ─────────────────────────────────────────────
// Brutto-Preise → Netto + Steuer (nur Integer, kein Float)

export function calcVat(grossCents: number, rate: '7' | '19'): { netCents: number; taxCents: number } {
  const divisor = rate === '19' ? 119 : 107;
  const netCents = Math.round((grossCents * 100) / divisor);
  return { netCents, taxCents: grossCents - netCents };
}

export function buildVatBreakdown(items: Array<{ vat_rate: '7' | '19'; subtotal_cents: number }>) {
  let vat7NetCents  = 0;
  let vat7TaxCents  = 0;
  let vat19NetCents = 0;
  let vat19TaxCents = 0;

  for (const item of items) {
    const { netCents, taxCents } = calcVat(item.subtotal_cents, item.vat_rate);
    if (item.vat_rate === '7') {
      vat7NetCents  += netCents;
      vat7TaxCents  += taxCents;
    } else {
      vat19NetCents += netCents;
      vat19TaxCents += taxCents;
    }
  }

  return { vat7NetCents, vat7TaxCents, vat19NetCents, vat19TaxCents };
}

// ─── POST /orders/:id/pay ─────────────────────────────────────────────────────

export async function payOrder(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const userId    = req.auth!.userId;
  const deviceId  = req.auth!.deviceId;
  const sessionId = req.sessionId!;
  const orderId   = Number(req.params['id']);

  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'Ungültige Order-ID.' });
    return;
  }

  const { payments } = req.body as z.infer<typeof payOrderSchema>;
  const paidTotal = payments.reduce((s, p) => s + p.amount_cents, 0);

  // Schnell-Checks vor der TX: Order + Tenant + Status
  const [orderRows] = await db.execute<any[]>(
    `SELECT o.id, o.status, o.table_id, o.is_takeaway
     FROM orders o WHERE o.id = ? AND o.tenant_id = ?`,
    [orderId, tenantId]
  );
  if (orderRows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }
  if (orderRows[0].status !== 'open') {
    res.status(409).json({ error: 'Bestellung ist nicht mehr offen.' });
    return;
  }

  // Items laden (für MwSt-Berechnung + Bon-Snapshot)
  const [items] = await db.execute<any[]>(
    `SELECT oi.id, oi.product_name, oi.product_price_cents, oi.vat_rate,
            oi.quantity, oi.subtotal_cents, oi.discount_cents, oi.discount_reason
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE oi.order_id = ? AND o.tenant_id = ?
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`,
    [orderId, tenantId]
  );
  if (items.length === 0) {
    res.status(422).json({ error: 'Bestellung hat keine Positionen.' });
    return;
  }

  // Gesamtbetrag prüfen (Summe aller Zahlungsmittel muss Order-Total ergeben)
  const totalCents = items.reduce((s: number, i: any) => s + i.subtotal_cents, 0);
  if (paidTotal !== totalCents) {
    res.status(422).json({
      error: `Betrag stimmt nicht: erwartet ${totalCents} Cent, erhalten ${paidTotal} Cent.`,
      expected_cents: totalCents,
    });
    return;
  }

  // Tenant + Device-Snapshots für Bon-Pflichtfelder (§ 14 UStG, KassenSichV)
  const [tenantRows] = await db.execute<any[]>(
    'SELECT name, address, vat_id, tax_number FROM tenants WHERE id = ?',
    [tenantId]
  );
  const [deviceRows] = await db.execute<any[]>(
    'SELECT id, name FROM devices WHERE id = ? AND tenant_id = ?',
    [deviceId, tenantId]
  );
  if (deviceRows.length === 0) { res.status(500).json({ error: 'Gerät nicht gefunden.' }); return; }

  const tenant = tenantRows[0];
  const device = deviceRows[0];

  // MwSt-Aufschlüsselung
  const vat = buildVatBreakdown(items);

  // ─── Fiskaly TSE-Transaktion (vor DB-TX, damit Receipt einmalig korrekt geschrieben wird) ──
  // GoBD: Receipt wird NUR EINMAL geschrieben — entweder mit TSE-Daten oder mit tse_pending=TRUE
  const [tenantTseRow] = await db.execute<any[]>(
    'SELECT fiskaly_tss_id FROM tenants WHERE id = ?', [tenantId]
  );
  const [deviceTseRow] = await db.execute<any[]>(
    'SELECT tse_client_id FROM devices WHERE id = ? AND tenant_id = ?', [deviceId, tenantId]
  );

  const tseResult = await processTseTransaction({
    tenantId, deviceId, orderId, userId,
    tssId:           tenantTseRow[0]?.fiskaly_tss_id ?? '',
    clientId:        deviceTseRow[0]?.tse_client_id  ?? '',
    vat7GrossCents:  vat.vat7NetCents + vat.vat7TaxCents,
    vat19GrossCents: vat.vat19NetCents + vat.vat19TaxCents,
    payments,
  });

  // ─── DB-Transaktion: Bon-Nummer + Receipt + Payment + Order-Status ────────
  const conn = await db.getConnection();
  let receiptId: number;
  let receiptNumber: number | null = null;  // null bis vergeben — für Voided-Receipt-Fallback

  try {
    await conn.beginTransaction();

    // Order erneut sperren (Race-Condition-Schutz)
    const [lockedOrder] = await conn.execute<any[]>(
      `SELECT id, status FROM orders WHERE id = ? AND tenant_id = ? FOR UPDATE`,
      [orderId, tenantId]
    );
    if (lockedOrder[0].status !== 'open') {
      await conn.rollback();
      res.status(409).json({ error: 'Bestellung wurde zwischenzeitlich geändert.' });
      return;
    }

    // Bon-Nummer atomar vergeben (KassenSichV: fortlaufend, keine Lücken)
    receiptNumber = await nextReceiptNumber(tenantId, conn);

    // raw_receipt_json — unveränderlicher Snapshot aller Bon-Pflichtfelder
    const now = new Date().toISOString();
    const rawReceiptJson = {
      receipt_number:  receiptNumber,
      created_at:      now,
      tenant: {
        name:        tenant.name,
        address:     tenant.address,
        vat_id:      tenant.vat_id   ?? null,
        tax_number:  tenant.tax_number ?? null,
      },
      device: { id: device.id, name: device.name },
      items: items.map((i: any) => ({
        product_name:        i.product_name,
        product_price_cents: i.product_price_cents,
        vat_rate:            i.vat_rate,
        quantity:            i.quantity,
        subtotal_cents:      i.subtotal_cents,
        discount_cents:      i.discount_cents,
        discount_reason:     i.discount_reason ?? null,
      })),
      vat_7_net_cents:   vat.vat7NetCents,
      vat_7_tax_cents:   vat.vat7TaxCents,
      vat_19_net_cents:  vat.vat19NetCents,
      vat_19_tax_cents:  vat.vat19TaxCents,
      total_gross_cents: totalCents,
      payments:          payments.map(p => ({ method: p.method, amount_cents: p.amount_cents })),
      tse_pending:       tseResult.pending,
      tse_transaction_id: tseResult.tseTransactionId ?? null,
    };

    // Receipt INSERT (GoBD: NUR EINMAL, mit finalen TSE-Daten oder tse_pending=TRUE)
    const [receiptResult] = await conn.execute<any>(
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
        tenantId, orderId, sessionId, receiptNumber,
        device.id, device.name,
        vat.vat7NetCents, vat.vat7TaxCents, vat.vat19NetCents, vat.vat19TaxCents,
        totalCents, orderRows[0].is_takeaway,
        tseResult.pending ? 1 : 0,
        tseResult.tseTransactionId    ?? null,
        tseResult.tseSerialNumber     ?? null,
        tseResult.tseSignature        ?? null,
        tseResult.tseCounter          ?? null,
        tseResult.tseTransactionStart ?? null,
        tseResult.tseTransactionEnd   ?? null,
        JSON.stringify(rawReceiptJson),
      ]
    );
    receiptId = receiptResult.insertId as number;

    // Payments INSERT — ein Eintrag pro Zahlungsmittel (GoBD: NUR INSERT)
    for (const p of payments) {
      await conn.execute(
        `INSERT INTO payments (order_id, receipt_id, method, amount_cents, tip_cents, paid_by_user_id)
         VALUES (?, ?, ?, ?, 0, ?)`,
        [orderId, receiptId, p.method, p.amount_cents, userId]
      );
    }

    // Order auf 'paid' setzen
    await conn.execute(
      `UPDATE orders SET status = 'paid', closed_at = NOW() WHERE id = ? AND tenant_id = ?`,
      [orderId, tenantId]
    );

    // Offline-Queue-Eintrag mit receipt_id verknüpfen (für spätere TSE-Nachsignierung)
    if (tseResult.pending && tseResult.idempotencyKey) {
      await conn.execute(
        `UPDATE offline_queue SET payload_json = JSON_SET(payload_json, '$.receipt_id', ?)
         WHERE idempotency_key = ? AND tenant_id = ?`,
        [receiptId, tseResult.idempotencyKey, tenantId]
      );
    }

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    // GoBD: Bon-Nummer vergeben → TX fehlgeschlagen → Voided-Receipt anlegen (best-effort)
    if (receiptNumber !== null) {
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
            [tenantId, orderId, sessionId, voidNum, device.id, device.name]
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

  // Audit-Log außerhalb der TX (nicht-fatal)
  await writeAuditLog({
    tenantId, userId, action: 'order.paid',
    entityType: 'receipt', entityId: receiptId!,
    diff: { new: { receipt_number: receiptNumber!, payments, total_cents: totalCents, order_id: orderId } },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({
    receipt_id:           receiptId!,
    receipt_number:       receiptNumber!,
    total_gross_cents:    totalCents,
    vat_7_net_cents:      vat.vat7NetCents,
    vat_7_tax_cents:      vat.vat7TaxCents,
    vat_19_net_cents:     vat.vat19NetCents,
    vat_19_tax_cents:     vat.vat19TaxCents,
    payments,
    tse_pending:          tseResult.pending,
    tse_transaction_id:   tseResult.tseTransactionId   ?? null,
    tse_serial_number:    tseResult.tseSerialNumber     ?? null,
    tse_counter:          tseResult.tseCounter          ?? null,
  });
}

import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { nextReceiptNumber } from '../services/sequences.js';
import { processTseTransaction } from '../services/fiskaly.js';
import { buildVatBreakdown } from './paymentsController.js';

// ─── Schema ───────────────────────────────────────────────────────────────────

const paymentItemSchema = z.object({
  method:       z.enum(['cash', 'card']),
  amount_cents: z.number().int().positive(),
});

const splitSchema = z.object({
  order_item_ids: z.array(z.number().int().positive()).min(1),
  payments:       z.array(paymentItemSchema).min(1),
});

export const splitBillSchema = z.object({
  splits: z.array(splitSchema).min(1),
});

// ─── POST /orders/:id/pay/split ───────────────────────────────────────────────

export async function splitBill(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const userId    = req.auth!.userId;
  const deviceId  = req.auth!.deviceId;
  const sessionId = req.sessionId!;
  const orderId   = Number(req.params['id']);

  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'Ungültige Order-ID.' });
    return;
  }

  const { splits } = req.body as z.infer<typeof splitBillSchema>;

  // ─── Order laden ──────────────────────────────────────────────────────────
  const [orderRows] = await db.execute<any[]>(
    `SELECT id, status, is_takeaway FROM orders WHERE id = ? AND tenant_id = ?`,
    [orderId, tenantId]
  );
  if (orderRows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }
  if (orderRows[0].status !== 'open') {
    res.status(409).json({ error: 'Bestellung ist nicht mehr offen.' });
    return;
  }

  // ─── Alle Order-Items laden ───────────────────────────────────────────────
  const [allItems] = await db.execute<any[]>(
    `SELECT oi.id, oi.product_name, oi.product_price_cents, oi.vat_rate,
            oi.quantity, oi.subtotal_cents, oi.discount_cents, oi.discount_reason
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE oi.order_id = ? AND o.tenant_id = ?
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`,
    [orderId, tenantId]
  );
  if (allItems.length === 0) {
    res.status(422).json({ error: 'Bestellung hat keine Positionen.' });
    return;
  }

  const allItemIds = new Set(allItems.map((i: any) => i.id as number));
  const itemById   = new Map(allItems.map((i: any) => [i.id as number, i]));

  // ─── Splits validieren ────────────────────────────────────────────────────

  // 1. Keine unbekannten Item-IDs
  const requestedIds: number[] = splits.flatMap(s => s.order_item_ids);
  const unknownIds = requestedIds.filter(id => !allItemIds.has(id));
  if (unknownIds.length > 0) {
    res.status(422).json({ error: `Unbekannte order_item_ids: ${unknownIds.join(', ')}.` });
    return;
  }

  // 2. Keine Überschneidungen (jedes Item max. einmal)
  const seen = new Set<number>();
  for (const id of requestedIds) {
    if (seen.has(id)) {
      res.status(422).json({ error: `order_item_id ${id} kommt in mehreren Splits vor.` });
      return;
    }
    seen.add(id);
  }

  // 3. Alle Items abgedeckt
  if (seen.size !== allItemIds.size) {
    const missing = [...allItemIds].filter(id => !seen.has(id));
    res.status(422).json({ error: `Folgende Items fehlen in den Splits: ${missing.join(', ')}.` });
    return;
  }

  // 4. Zahlungssumme je Split muss Item-Summe ergeben
  for (let i = 0; i < splits.length; i++) {
    const split       = splits[i];
    const itemTotal   = split.order_item_ids.reduce((s, id) => s + (itemById.get(id)?.subtotal_cents ?? 0), 0);
    const payTotal    = split.payments.reduce((s, p) => s + p.amount_cents, 0);
    if (payTotal !== itemTotal) {
      res.status(422).json({
        error:          `Split ${i + 1}: Betrag stimmt nicht.`,
        expected_cents: itemTotal,
        received_cents: payTotal,
      });
      return;
    }
  }

  // ─── Tenant + Device-Snapshots ────────────────────────────────────────────
  const [tenantRows] = await db.execute<any[]>(
    'SELECT name, address, vat_id, tax_number, fiskaly_tss_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  const [deviceRows] = await db.execute<any[]>(
    'SELECT id, name, tse_client_id FROM devices WHERE id = ? AND tenant_id = ?',
    [deviceId, tenantId]
  );
  if (deviceRows.length === 0) { res.status(500).json({ error: 'Gerät nicht gefunden.' }); return; }

  const tenant = tenantRows[0];
  const device = deviceRows[0];

  // ─── TSE-Transaktionen (eine pro Split, vor DB-TX) ────────────────────────
  // GoBD: Receipts werden NUR EINMAL geschrieben — je Split mit finalen TSE-Daten
  const tseResults = [];
  for (const split of splits) {
    const splitItems  = split.order_item_ids.map(id => itemById.get(id)!);
    const vat         = buildVatBreakdown(splitItems);
    const tseResult   = await processTseTransaction({
      tenantId, deviceId, orderId, userId,
      tssId:           tenant.fiskaly_tss_id ?? '',
      clientId:        device.tse_client_id  ?? '',
      vat7GrossCents:  vat.vat7NetCents + vat.vat7TaxCents,
      vat19GrossCents: vat.vat19NetCents + vat.vat19TaxCents,
      payments:        split.payments,
    });
    tseResults.push(tseResult);
  }

  // ─── DB-Transaktion: alle Splits atomar ───────────────────────────────────
  const conn = await db.getConnection();
  let allocatedCount = 0;  // zählt nextReceiptNumber-Aufrufe für Voided-Receipt-Fallback
  const createdReceipts: Array<{
    receipt_id: number; receipt_number: number;
    split_index: number; total_gross_cents: number; tse_pending: boolean;
  }> = [];

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

    const splitGroupId = orderId; // orderId als gemeinsame Gruppen-ID aller Split-Bons
    const now = new Date().toISOString();

    for (let i = 0; i < splits.length; i++) {
      const split      = splits[i];
      const tseResult  = tseResults[i];
      const splitItems = split.order_item_ids.map(id => itemById.get(id)!);
      const vat        = buildVatBreakdown(splitItems);
      const splitTotal = splitItems.reduce((s: number, item: any) => s + item.subtotal_cents, 0);

      // Bon-Nummer atomar vergeben
      const receiptNumber = await nextReceiptNumber(tenantId, conn);
      allocatedCount++;

      // raw_receipt_json — Snapshot nur der Items dieses Splits
      const rawReceiptJson = {
        receipt_number:  receiptNumber,
        split_index:     i + 1,
        split_total:     splits.length,
        created_at:      now,
        tenant: {
          name:       tenant.name,
          address:    tenant.address,
          vat_id:     tenant.vat_id     ?? null,
          tax_number: tenant.tax_number ?? null,
        },
        device:  { id: device.id, name: device.name },
        items:   splitItems.map((item: any) => ({
          product_name:        item.product_name,
          product_price_cents: item.product_price_cents,
          vat_rate:            item.vat_rate,
          quantity:            item.quantity,
          subtotal_cents:      item.subtotal_cents,
          discount_cents:      item.discount_cents,
          discount_reason:     item.discount_reason ?? null,
        })),
        vat_7_net_cents:   vat.vat7NetCents,
        vat_7_tax_cents:   vat.vat7TaxCents,
        vat_19_net_cents:  vat.vat19NetCents,
        vat_19_tax_cents:  vat.vat19TaxCents,
        total_gross_cents: splitTotal,
        payments:          split.payments,
        tse_pending:       tseResult.pending,
        tse_transaction_id: tseResult.tseTransactionId ?? null,
      };

      // Receipt INSERT (GoBD: NUR EINMAL, status='active')
      const [receiptResult] = await conn.execute<any>(
        `INSERT INTO receipts
           (tenant_id, order_id, session_id, receipt_number, status,
            device_id, device_name, is_split_receipt, split_group_id,
            vat_7_net_cents, vat_7_tax_cents, vat_19_net_cents, vat_19_tax_cents,
            total_gross_cents, tip_cents, is_takeaway,
            tse_pending, tse_transaction_id, tse_serial_number, tse_signature,
            tse_counter, tse_transaction_start, tse_transaction_end,
            raw_receipt_json)
         VALUES (?, ?, ?, ?, 'active', ?, ?, TRUE, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          tenantId, orderId, sessionId, receiptNumber,
          device.id, device.name, splitGroupId,
          vat.vat7NetCents, vat.vat7TaxCents, vat.vat19NetCents, vat.vat19TaxCents,
          splitTotal, orderRows[0].is_takeaway,
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
      const receiptId = receiptResult.insertId as number;

      // Payments INSERT — ein Eintrag pro Zahlungsmittel dieses Splits
      for (const p of split.payments) {
        await conn.execute(
          `INSERT INTO payments (order_id, receipt_id, method, amount_cents, tip_cents, paid_by_user_id)
           VALUES (?, ?, ?, ?, 0, ?)`,
          [orderId, receiptId, p.method, p.amount_cents, userId]
        );
      }

      // payment_splits INSERT
      await conn.execute(
        `INSERT INTO payment_splits (order_id, receipt_id, items_json, total_cents, created_by_user_id)
         VALUES (?, ?, ?, ?, ?)`,
        [orderId, receiptId, JSON.stringify(split.order_item_ids), splitTotal, userId]
      );

      createdReceipts.push({
        receipt_id:        receiptId,
        receipt_number:    receiptNumber,
        split_index:       i + 1,
        total_gross_cents: splitTotal,
        tse_pending:       tseResult.pending,
      });
    }

    // Order auf 'paid' setzen
    await conn.execute(
      `UPDATE orders SET status = 'paid', closed_at = NOW() WHERE id = ? AND tenant_id = ?`,
      [orderId, tenantId]
    );

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    // GoBD: vergebene Bon-Nummern → TX fehlgeschlagen → Voided-Receipts anlegen (best-effort)
    if (allocatedCount > 0) {
      const voidConn = await db.getConnection().catch(() => null);
      if (voidConn) {
        try {
          await voidConn.beginTransaction();
          for (let i = 0; i < allocatedCount; i++) {
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
          }
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
  const orderTotal = allItems.reduce((s: number, i: any) => s + i.subtotal_cents, 0);
  await writeAuditLog({
    tenantId, userId, action: 'order.split_paid',
    entityType: 'order', entityId: orderId,
    diff: {
      new: {
        split_count:    splits.length,
        receipt_ids:    createdReceipts.map(r => r.receipt_id),
        total_cents:    orderTotal,
      },
    },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({ receipts: createdReceipts });
}

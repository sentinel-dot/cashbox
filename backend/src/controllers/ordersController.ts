import { Request, Response } from 'express';
import { z } from 'zod';
import { db, auditDb } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ─────────────────────────────────────────────────────────────────

export const createOrderSchema = z.object({
  table_id: z.number().int().positive().optional(),
});

export const addItemSchema = z.object({
  product_id:          z.number().int().positive(),
  quantity:            z.number().int().min(1).default(1),
  modifier_option_ids: z.array(z.number().int().positive()).optional(),
  discount_cents:      z.number().int().nonnegative().optional(),
  discount_reason:     z.string().min(1).max(500).optional(),
}).refine(
  d => d.discount_cents === undefined || d.discount_cents === 0 || !!d.discount_reason,
  { message: 'discount_reason ist Pflichtfeld wenn discount_cents > 0 (GoBD).', path: ['discount_reason'] }
);

export const cancelOrderSchema = z.object({
  reason: z.string().min(1).max(1000),
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Liest alle Items + Modifikatoren einer Order als nested Array. */
async function fetchOrderItems(orderId: number, tenantId: number) {
  const [items] = await db.execute<any[]>(
    `SELECT oi.id, oi.product_id, oi.product_name, oi.product_price_cents,
            oi.vat_rate, oi.quantity, oi.subtotal_cents,
            oi.discount_cents, oi.discount_reason, oi.created_at
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE oi.order_id = ? AND o.tenant_id = ?
       AND NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)
     ORDER BY oi.created_at ASC`,
    [orderId, tenantId]
  );

  if (items.length === 0) return [];

  const [modifiers] = await db.execute<any[]>(
    `SELECT oim.order_item_id, oim.modifier_option_id, oim.option_name, oim.price_delta_cents
     FROM order_item_modifiers oim
     JOIN order_items oi ON oi.id = oim.order_item_id
     JOIN orders o ON o.id = oi.order_id
     WHERE oi.order_id = ? AND o.tenant_id = ?`,
    [orderId, tenantId]
  );

  const modsByItem = new Map<number, any[]>();
  for (const m of modifiers) {
    const list = modsByItem.get(m.order_item_id) ?? [];
    list.push({ modifier_option_id: m.modifier_option_id, name: m.option_name, price_delta_cents: m.price_delta_cents });
    modsByItem.set(m.order_item_id, list);
  }

  return items.map(i => ({ ...i, modifiers: modsByItem.get(i.id) ?? [] }));
}

// ─── GET /orders ──────────────────────────────────────────────────────────────

export async function listOrders(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const sessionId = req.sessionId!;

  const [orders] = await db.execute<any[]>(
    `SELECT o.id, o.status, o.is_takeaway, o.created_at, o.closed_at,
            t.id AS table_id, t.name AS table_name,
            u.name AS opened_by_name
     FROM orders o
     LEFT JOIN tables t ON t.id = o.table_id
     JOIN users u ON u.id = o.opened_by_user_id
     WHERE o.tenant_id = ? AND o.session_id = ? AND o.status = 'open'
     ORDER BY o.created_at ASC`,
    [tenantId, sessionId]
  );

  res.json(orders.map(o => ({
    id:             o.id,
    status:         o.status,
    is_takeaway:    o.is_takeaway,
    created_at:     o.created_at,
    opened_by_name: o.opened_by_name,
    table: o.table_id ? { id: o.table_id, name: o.table_name } : null,
  })));
}

// ─── POST /orders ─────────────────────────────────────────────────────────────

export async function createOrder(req: Request, res: Response): Promise<void> {
  const tenantId  = req.auth!.tenantId;
  const userId    = req.auth!.userId;
  const sessionId = req.sessionId!;
  const { table_id } = req.body as z.infer<typeof createOrderSchema>;

  // Tisch-Zugehörigkeit prüfen wenn angegeben
  if (table_id !== undefined) {
    const [tableRows] = await db.execute<any[]>(
      'SELECT id FROM tables WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
      [table_id, tenantId]
    );
    if (tableRows.length === 0) {
      res.status(404).json({ error: 'Tisch nicht gefunden.' });
      return;
    }
  }

  const [result] = await db.execute<any>(
    `INSERT INTO orders (tenant_id, table_id, session_id, opened_by_user_id, is_takeaway)
     VALUES (?, ?, ?, ?, FALSE)`,
    [tenantId, table_id ?? null, sessionId, userId]
  );
  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId, action: 'order.created',
    entityType: 'order', entityId: newId,
    diff: { new: { table_id: table_id ?? null, session_id: sessionId } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, status: 'open', table_id: table_id ?? null, session_id: sessionId });
}

// ─── GET /orders/:id ──────────────────────────────────────────────────────────

export async function getOrder(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const orderId  = Number(req.params['id']);
  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'Ungültige Order-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    `SELECT o.id, o.status, o.is_takeaway, o.created_at, o.closed_at, o.session_id,
            t.id AS table_id, t.name AS table_name,
            u.name AS opened_by_name
     FROM orders o
     LEFT JOIN tables t ON t.id = o.table_id
     JOIN users u ON u.id = o.opened_by_user_id
     WHERE o.id = ? AND o.tenant_id = ?`,
    [orderId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }

  const items = await fetchOrderItems(orderId, tenantId);
  const total_cents = items.reduce((s: number, i: any) => s + i.subtotal_cents, 0);

  const o = rows[0];
  res.json({
    id:             o.id,
    status:         o.status,
    is_takeaway:    o.is_takeaway,
    created_at:     o.created_at,
    closed_at:      o.closed_at,
    session_id:     o.session_id,
    opened_by_name: o.opened_by_name,
    table: o.table_id ? { id: o.table_id, name: o.table_name } : null,
    items,
    total_cents,
  });
}

// ─── POST /orders/:id/items ───────────────────────────────────────────────────

export async function addItem(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;
  const orderId  = Number(req.params['id']);
  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'Ungültige Order-ID.' });
    return;
  }

  const { product_id, quantity, modifier_option_ids, discount_cents, discount_reason } =
    req.body as z.infer<typeof addItemSchema>;

  // Order prüfen — muss offen und zum Tenant gehören
  const [orderRows] = await db.execute<any[]>(
    'SELECT id, status FROM orders WHERE id = ? AND tenant_id = ?',
    [orderId, tenantId]
  );
  if (orderRows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }
  if (orderRows[0].status !== 'open') {
    res.status(409).json({ error: 'Bestellung ist nicht mehr offen.' });
    return;
  }

  // Produkt + Preis-Snapshot holen — muss zum Tenant gehören
  const [productRows] = await db.execute<any[]>(
    `SELECT id, name, price_cents, vat_rate_inhouse, category_id
     FROM products WHERE id = ? AND tenant_id = ? AND is_active = TRUE`,
    [product_id, tenantId]
  );
  if (productRows.length === 0) { res.status(404).json({ error: 'Produkt nicht gefunden.' }); return; }
  const product = productRows[0];

  // Modifier-Optionen validieren
  let optRows: any[] = [];
  if (modifier_option_ids?.length) {
    const placeholders = modifier_option_ids.map(() => '?').join(',');
    const [rows] = await db.execute<any[]>(
      `SELECT o.id, o.name, o.price_delta_cents, g.id AS group_id,
              g.product_id AS group_product_id, g.category_id AS group_category_id
       FROM product_modifier_options o
       JOIN product_modifier_groups g ON g.id = o.modifier_group_id
       WHERE o.id IN (${placeholders}) AND o.tenant_id = ? AND o.is_active = TRUE AND g.is_active = TRUE`,
      [...modifier_option_ids, tenantId]
    );
    if (rows.length !== modifier_option_ids.length) {
      res.status(403).json({ error: 'Ungültige modifier_option_ids — nicht gefunden oder falsche Tenant-Zugehörigkeit.' });
      return;
    }
    for (const opt of rows) {
      const belongsToProduct  = opt.group_product_id === product.id;
      const belongsToCategory = opt.group_category_id !== null && opt.group_category_id === product.category_id;
      if (!belongsToProduct && !belongsToCategory) {
        res.status(403).json({ error: `Option ${opt.id} gehört nicht zu Produkt ${product.id}.` });
        return;
      }
    }
    optRows = rows;
  }

  // Required Modifier-Gruppen prüfen — auch wenn keine Optionen übergeben wurden
  const [requiredGroups] = await db.execute<any[]>(
    `SELECT id FROM product_modifier_groups
     WHERE (product_id = ? OR category_id = ?) AND tenant_id = ? AND is_required = TRUE AND is_active = TRUE`,
    [product.id, product.category_id ?? -1, tenantId]
  );
  const coveredGroupIds = new Set(optRows.map((o: any) => o.group_id));
  for (const rg of requiredGroups) {
    if (!coveredGroupIds.has(rg.id)) {
      res.status(422).json({ error: `Pflicht-Modifier-Gruppe ${rg.id} nicht abgedeckt.` });
      return;
    }
  }

  const modifierDeltaTotal = optRows.reduce((s: number, o: any) => s + o.price_delta_cents, 0);

  // Berechnung: (price_cents + SUM(modifier_deltas)) × quantity - discount_cents
  const discountCents = discount_cents ?? 0;
  const subtotal_cents = (product.price_cents + modifierDeltaTotal) * quantity - discountCents;
  if (subtotal_cents < 0) {
    res.status(422).json({ error: 'Rabatt darf den Positionsbetrag nicht überschreiten.' });
    return;
  }

  // order_items INSERT (GoBD: Snapshots)
  const [itemResult] = await db.execute<any>(
    `INSERT INTO order_items
       (order_id, product_id, product_name, product_price_cents, vat_rate,
        quantity, subtotal_cents, discount_cents, discount_reason, added_by_user_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      orderId, product.id, product.name, product.price_cents,
      product.vat_rate_inhouse, quantity, subtotal_cents,
      discountCents, discount_reason ?? null, userId,
    ]
  );
  const itemId = itemResult.insertId as number;

  // order_item_modifiers via auditDb (INSERT-only per DB-User)
  for (const opt of optRows) {
    await auditDb.execute(
      `INSERT INTO order_item_modifiers (order_item_id, modifier_option_id, option_name, price_delta_cents)
       VALUES (?, ?, ?, ?)`,
      [itemId, opt.id, opt.name, opt.price_delta_cents]
    );
  }

  await writeAuditLog({
    tenantId, userId, action: 'order.item_added',
    entityType: 'order_item', entityId: itemId,
    diff: { new: { order_id: orderId, product_id, quantity, subtotal_cents, discount_cents: discountCents } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: itemId, product_id, product_name: product.name, subtotal_cents, quantity });
}

// ─── DELETE /orders/:id/items/:itemId ────────────────────────────────────────
// GoBD-Hinweis: Entfernen ist nur vor Zahlung (kein Bon) erlaubt.
// Audit-Log dokumentiert die Entfernung; TSE ist noch nicht involviert.

export async function removeItem(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;
  const orderId  = Number(req.params['id']);
  const itemId   = Number(req.params['itemId']);

  if (!Number.isInteger(orderId) || orderId <= 0 || !Number.isInteger(itemId) || itemId <= 0) {
    res.status(400).json({ error: 'Ungültige ID.' });
    return;
  }

  // Order prüfen
  const [orderRows] = await db.execute<any[]>(
    'SELECT id, status FROM orders WHERE id = ? AND tenant_id = ?',
    [orderId, tenantId]
  );
  if (orderRows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }
  if (orderRows[0].status !== 'open') {
    res.status(409).json({ error: 'Bestellung ist nicht mehr offen — Storno über /cancel.' });
    return;
  }

  // Item prüfen
  const [itemRows] = await db.execute<any[]>(
    'SELECT id, product_name, subtotal_cents FROM order_items WHERE id = ? AND order_id = ?',
    [itemId, orderId]
  );
  if (itemRows.length === 0) { res.status(404).json({ error: 'Position nicht gefunden.' }); return; }

  // Bereits bezahlt? (receipts mit status='active' verhindern Löschen)
  const [receiptRows] = await db.execute<any[]>(
    `SELECT r.id FROM receipts r WHERE r.order_id = ? AND r.status = 'active' LIMIT 1`,
    [orderId]
  );
  if (receiptRows.length > 0) {
    res.status(409).json({ error: 'Bestellung hat bereits einen aktiven Bon — Storno über /cancel.' });
    return;
  }

  // GoBD: kein DELETE — Entfernung wird in order_item_removals dokumentiert (INSERT-only, append-only)
  await db.execute(
    'INSERT INTO order_item_removals (order_item_id, removed_by_user_id) VALUES (?, ?)',
    [itemId, userId]
  );

  await writeAuditLog({
    tenantId, userId, action: 'order.item_removed',
    entityType: 'order_item', entityId: itemId,
    diff: { old: { order_id: orderId, product_name: itemRows[0].product_name, subtotal_cents: itemRows[0].subtotal_cents } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── POST /orders/:id/cancel ──────────────────────────────────────────────────

export async function cancelOrder(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;
  const orderId  = Number(req.params['id']);
  if (!Number.isInteger(orderId) || orderId <= 0) {
    res.status(400).json({ error: 'Ungültige Order-ID.' });
    return;
  }

  const { reason } = req.body as z.infer<typeof cancelOrderSchema>;

  const [orderRows] = await db.execute<any[]>(
    'SELECT id, status FROM orders WHERE id = ? AND tenant_id = ?',
    [orderId, tenantId]
  );
  if (orderRows.length === 0) { res.status(404).json({ error: 'Bestellung nicht gefunden.' }); return; }
  if (orderRows[0].status === 'cancelled') {
    res.status(409).json({ error: 'Bestellung ist bereits storniert.' });
    return;
  }
  if (orderRows[0].status === 'paid') {
    res.status(409).json({ error: 'Bezahlte Bestellungen müssen über den Storno-Bon-Flow storniert werden (Phase 2).' });
    return;
  }

  // Nur offene Orders (kein Bon) können direkt storniert werden
  await db.execute(
    `UPDATE orders SET status = 'cancelled', closed_at = NOW() WHERE id = ? AND tenant_id = ?`,
    [orderId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId, action: 'order.cancelled',
    entityType: 'order', entityId: orderId,
    diff: { old: { status: 'open' }, new: { status: 'cancelled', reason } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

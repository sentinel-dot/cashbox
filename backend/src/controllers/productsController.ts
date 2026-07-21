import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { writePriceHistory } from '../services/priceHistory.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const createCategorySchema = z.object({
  name:       z.string().min(1).max(255),
  color:      z.string().regex(/^#[0-9a-fA-F]{6}$/).nullable().optional(),
  sort_order: z.number().int().nonnegative().optional(),
});

export const updateCategorySchema = z.object({
  name:       z.string().min(1).max(255).optional(),
  color:      z.string().regex(/^#[0-9a-fA-F]{6}$/).nullable().optional(),
  sort_order: z.number().int().nonnegative().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

export const createProductSchema = z.object({
  name:               z.string().min(1).max(255),
  category_id:        z.number().int().positive().nullable().optional(),
  price_cents:        z.number().int().nonnegative(),
  vat_rate_inhouse:   z.enum(['7', '19']),
  vat_rate_takeaway:  z.enum(['7', '19']).optional(),
  sort_order:         z.number().int().nonnegative().optional(),
});

// price_cents + vat_rate_* sind IMMUTABLE — hier explizit verboten
export const updateProductSchema = z.object({
  name:        z.string().min(1).max(255).optional(),
  category_id: z.number().int().positive().nullable().optional(),
  is_active:   z.boolean().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

export const changePriceSchema = z.object({
  price_cents:       z.number().int().nonnegative(),
  vat_rate_inhouse:  z.enum(['7', '19']).optional(),
  vat_rate_takeaway: z.enum(['7', '19']).optional(),
});

// GET /products: validationMiddleware validiert nur req.body — Query-Params
// werden im Controller via safeParse geprüft (CLAUDE.md-Regel).
// include_inactive=1 ist die Management-Ansicht (Sortiment); die Kasse nutzt
// den Default und sieht weiterhin ausschließlich aktive Produkte.
export const listProductsQuerySchema = z.object({
  include_inactive: z.enum(['0', '1']).optional(),
}).strict();

export const reorderProductsSchema = z.object({
  category_id: z.number().int().positive().nullable(),
  product_ids: z.array(z.number().int().positive()).min(1).max(500)
    .refine(ids => new Set(ids).size === ids.length, { message: 'product_ids enthält Duplikate.' }),
});

export const reorderCategoriesSchema = z.object({
  category_ids: z.array(z.number().int().positive()).min(1).max(500)
    .refine(ids => new Set(ids).size === ids.length, { message: 'category_ids enthält Duplikate.' }),
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

function forbiddenPriceFields(body: Record<string, unknown>): string | null {
  if ('price_cents' in body)       return 'price_cents';
  if ('vat_rate_inhouse' in body)  return 'vat_rate_inhouse';
  if ('vat_rate_takeaway' in body) return 'vat_rate_takeaway';
  return null;
}

// ─── Kategorien ──────────────────────────────────────────────────────────────

export async function listCategories(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const [rows] = await db.execute<any[]>(
    `SELECT id, name, color, sort_order, is_active
     FROM product_categories
     WHERE tenant_id = ? AND is_active = TRUE
     ORDER BY sort_order ASC, name ASC`,
    [tenantId]
  );
  res.json(rows);
}

export async function createCategory(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { name, color, sort_order } = req.body as z.infer<typeof createCategorySchema>;

  const [result] = await db.execute<any>(
    `INSERT INTO product_categories (tenant_id, name, color, sort_order)
     VALUES (?, ?, ?, ?)`,
    [tenantId, name, color ?? null, sort_order ?? 0]
  );

  const newId = result.insertId as number;
  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'category.created',
    entityType: 'product_category', entityId: newId,
    diff: { new: { name, color, sort_order } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, name, color: color ?? null, sort_order: sort_order ?? 0 });
}

export async function updateCategory(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Kategorie-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, color, sort_order FROM product_categories WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Kategorie nicht gefunden.' }); return; }

  const { name, color, sort_order } = req.body as z.infer<typeof updateCategorySchema>;
  const updates: string[] = [];
  const values: unknown[]  = [];

  if (name       !== undefined) { updates.push('name = ?');       values.push(name); }
  if (color      !== undefined) { updates.push('color = ?');      values.push(color); }
  if (sort_order !== undefined) { updates.push('sort_order = ?'); values.push(sort_order); }

  values.push(targetId, tenantId);
  await db.execute(
    `UPDATE product_categories SET ${updates.join(', ')} WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'category.updated',
    entityType: 'product_category', entityId: targetId,
    diff: { old: rows[0], new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function deleteCategory(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Kategorie-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name FROM product_categories WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Kategorie nicht gefunden.' }); return; }

  // Nur löschen wenn keine aktiven Produkte darin
  const [productCount] = await db.execute<any[]>(
    'SELECT COUNT(*) as cnt FROM products WHERE category_id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (productCount[0].cnt > 0) {
    res.status(409).json({ error: 'Kategorie enthält noch aktive Produkte. Bitte zuerst Produkte verschieben oder deaktivieren.' });
    return;
  }

  await db.execute(
    'UPDATE product_categories SET is_active = FALSE WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'category.deleted',
    entityType: 'product_category', entityId: targetId,
    diff: { old: { name: rows[0].name } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── Produkte ─────────────────────────────────────────────────────────────────

export async function listProducts(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const parsedQuery = listProductsQuerySchema.safeParse(req.query);
  if (!parsedQuery.success) {
    res.status(400).json({ error: 'Ungültige Query-Parameter.', details: parsedQuery.error.issues });
    return;
  }
  const includeInactive = parsedQuery.data.include_inactive === '1';

  // Alle Produkte + Kategorien in einer Query
  const [products] = await db.execute<any[]>(
    `SELECT p.id, p.name, p.price_cents, p.vat_rate_inhouse, p.vat_rate_takeaway,
            p.is_active, p.sort_order, p.created_at,
            c.id   AS category_id,
            c.name AS category_name,
            c.color AS category_color,
            c.sort_order AS category_sort_order
     FROM products p
     LEFT JOIN product_categories c ON c.id = p.category_id AND c.tenant_id = ?
     WHERE p.tenant_id = ?${includeInactive ? '' : ' AND p.is_active = TRUE'}
     ORDER BY (c.id IS NULL) ASC, c.sort_order ASC, c.name ASC, p.sort_order ASC, p.name ASC, p.id ASC`,
    [tenantId, tenantId]
  );

  // Alle Modifier-Gruppen + Optionen des Tenants
  const [groups] = await db.execute<any[]>(
    `SELECT id, product_id, category_id, name, is_required,
            min_selections, max_selections, sort_order
     FROM product_modifier_groups
     WHERE tenant_id = ? AND is_active = TRUE
     ORDER BY sort_order ASC`,
    [tenantId]
  );

  const [options] = await db.execute<any[]>(
    `SELECT o.id, o.modifier_group_id, o.name, o.price_delta_cents, o.sort_order
     FROM product_modifier_options o
     JOIN product_modifier_groups g ON g.id = o.modifier_group_id
     WHERE o.tenant_id = ? AND o.is_active = TRUE
     ORDER BY o.sort_order ASC`,
    [tenantId]
  );

  // Gruppen mit Optionen zusammenbauen
  const optionsByGroup = new Map<number, any[]>();
  for (const opt of options) {
    const list = optionsByGroup.get(opt.modifier_group_id) ?? [];
    list.push({ id: opt.id, name: opt.name, price_delta_cents: opt.price_delta_cents, sort_order: opt.sort_order });
    optionsByGroup.set(opt.modifier_group_id, list);
  }

  const groupsWithOptions = groups.map(g => ({
    ...g,
    options: optionsByGroup.get(g.id) ?? [],
  }));

  // Produkte mit nested Modifiers zusammenbauen
  const result = products.map(p => ({
    id:               p.id,
    name:             p.name,
    price_cents:      p.price_cents,
    vat_rate_inhouse: p.vat_rate_inhouse,
    vat_rate_takeaway: p.vat_rate_takeaway,
    is_active:        Boolean(p.is_active),   // MySQL TINYINT(1) → JS boolean
    sort_order:       p.sort_order,
    created_at:       p.created_at,
    category: p.category_id
      ? { id: p.category_id, name: p.category_name, color: p.category_color, sort_order: p.category_sort_order }
      : null,
    modifier_groups: groupsWithOptions
      .filter(g =>
        g.product_id === p.id ||
        (g.category_id !== null && g.category_id === p.category_id)
      )
      .map(g => ({
        ...g,
        is_required: Boolean(g.is_required),  // MySQL TINYINT(1) → JS boolean
        is_active:   Boolean(g.is_active),
      })),
  }));

  res.json(result);
}

export async function createProduct(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { name, category_id, price_cents, vat_rate_inhouse, vat_rate_takeaway, sort_order } =
    req.body as z.infer<typeof createProductSchema>;

  // Kategorie-Zugehörigkeit prüfen (nur wenn explizit eine ID angegeben)
  if (category_id != null) {
    const [catRows] = await db.execute<any[]>(
      'SELECT id FROM product_categories WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
      [category_id, tenantId]
    );
    if (catRows.length === 0) {
      res.status(404).json({ error: 'Kategorie nicht gefunden.' });
      return;
    }
  }

  const vatTakeaway = vat_rate_takeaway ?? vat_rate_inhouse;

  // Ohne expliziten sort_order ans Ende der Kategorie anhängen (Lücken von 10)
  let effectiveSortOrder = sort_order;
  if (effectiveSortOrder === undefined) {
    const [maxRows] = await db.execute<any[]>(
      `SELECT COALESCE(MAX(sort_order), 0) + 10 AS next_sort
       FROM products WHERE tenant_id = ? AND category_id <=> ?`,
      [tenantId, category_id ?? null]
    );
    effectiveSortOrder = maxRows[0].next_sort as number;
  }

  const [result] = await db.execute<any>(
    `INSERT INTO products (tenant_id, category_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [tenantId, category_id ?? null, name, price_cents, vat_rate_inhouse, vatTakeaway, effectiveSortOrder]
  );

  const newId = result.insertId as number;

  // GoBD: initialen Preis-Eintrag in product_price_history schreiben (auditDb = INSERT-only)
  await writePriceHistory({
    productId:       newId,
    tenantId,
    priceCents:      price_cents,
    vatRateInhouse:  vat_rate_inhouse,
    vatRateTakeaway: vatTakeaway,
    changedByUserId: req.auth!.userId,
  });

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'product.created',
    entityType: 'product', entityId: newId,
    diff: { new: { name, price_cents, vat_rate_inhouse } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({
    id: newId, name, price_cents, vat_rate_inhouse, vat_rate_takeaway: vatTakeaway,
    sort_order: effectiveSortOrder,
  });
}

export async function updateProduct(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Produkt-ID.' });
    return;
  }

  // Verbotene Felder explizit abweisen — GoBD: price_cents ist immutable
  const forbidden = forbiddenPriceFields(req.body);
  if (forbidden) {
    res.status(400).json({
      error: `'${forbidden}' darf nicht über PATCH geändert werden.`,
      hint: 'Preisänderungen erfordern einen neuen product_price_history-Eintrag (GoBD-Pflicht). Endpoint: POST /products/:id/price',
    });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, category_id, is_active FROM products WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Produkt nicht gefunden.' }); return; }

  const { name, category_id, is_active } = req.body as z.infer<typeof updateProductSchema>;

  // Kategorie-Zugehörigkeit prüfen wenn gesetzt
  if (category_id !== undefined && category_id !== null) {
    const [catRows] = await db.execute<any[]>(
      'SELECT id FROM product_categories WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
      [category_id, tenantId]
    );
    if (catRows.length === 0) {
      res.status(404).json({ error: 'Kategorie nicht gefunden.' });
      return;
    }
  }

  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name        !== undefined) { updates.push('name = ?');        values.push(name); }
  if (category_id !== undefined) { updates.push('category_id = ?'); values.push(category_id); }
  if (is_active   !== undefined) { updates.push('is_active = ?');   values.push(is_active); }

  values.push(targetId, tenantId);
  await db.execute(
    `UPDATE products SET ${updates.join(', ')}, updated_at = NOW() WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'product.updated',
    entityType: 'product', entityId: targetId,
    diff: { old: rows[0], new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── POST /products/:id/price ────────────────────────────────────────────────
// GoBD: jede Preisänderung wird zuerst lückenlos in product_price_history
// dokumentiert (INSERT-only via auditDb), danach wird products.price_cents als
// operativer aktueller Preis aktualisiert — addItem/listProducts lesen diese
// Spalte. Direkte Änderungen via PATCH /products/:id bleiben verboten.
// Reihenfolge Historie → UPDATE: schlägt das UPDATE fehl, existiert nur ein
// zusätzlicher Historien-Eintrag (append-only, unschädlich).

export async function changePrice(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;
  const deviceId = req.auth!.deviceId;
  const targetId = Number(req.params['id']);

  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Produkt-ID.' });
    return;
  }

  const { price_cents, vat_rate_inhouse, vat_rate_takeaway } =
    req.body as z.infer<typeof changePriceSchema>;

  const [rows] = await db.execute<any[]>(
    `SELECT id, price_cents, vat_rate_inhouse, vat_rate_takeaway
     FROM products WHERE id = ? AND tenant_id = ? AND is_active = TRUE`,
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Produkt nicht gefunden.' }); return; }

  const current = rows[0];
  const newVatInhouse  = vat_rate_inhouse  ?? current.vat_rate_inhouse;
  const newVatTakeaway = vat_rate_takeaway ?? current.vat_rate_takeaway;

  // GoBD: Historie zuerst (INSERT-only via auditDb) …
  await writePriceHistory({
    productId:       targetId,
    tenantId,
    priceCents:      price_cents,
    vatRateInhouse:  newVatInhouse,
    vatRateTakeaway: newVatTakeaway,
    changedByUserId: userId,
  });

  // … dann den operativen Preis aktualisieren — addItem/listProducts lesen products.price_cents
  await db.execute(
    `UPDATE products
     SET price_cents = ?, vat_rate_inhouse = ?, vat_rate_takeaway = ?, updated_at = NOW()
     WHERE id = ? AND tenant_id = ?`,
    [price_cents, newVatInhouse, newVatTakeaway, targetId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId, action: 'product.price_changed',
    entityType: 'product', entityId: targetId,
    diff: {
      old: { price_cents: current.price_cents, vat_rate_inhouse: current.vat_rate_inhouse },
      new: { price_cents, vat_rate_inhouse: newVatInhouse },
    },
    ipAddress: req.ip, deviceId,
  });

  res.status(201).json({ product_id: targetId, price_cents, vat_rate_inhouse: newVatInhouse, vat_rate_takeaway: newVatTakeaway });
}

export async function deleteProduct(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Produkt-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name FROM products WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Produkt nicht gefunden.' }); return; }

  await db.execute(
    'UPDATE products SET is_active = FALSE, updated_at = NOW() WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'product.deleted',
    entityType: 'product', entityId: targetId,
    diff: { old: { name: rows[0].name } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── Reorder (S17A) ──────────────────────────────────────────────────────────
// Vollständige geordnete ID-Liste je Scope; sort_order = (index+1)*10.
// Idempotent: gleiche Eingabe ⇒ gleicher Endzustand. Fremde/falsche IDs ⇒ 404
// (kein Informationsleck über fremde Tenants), nichts wird geändert.

async function applyReorder(
  table: 'products' | 'product_categories',
  ids: number[],
  tenantId: number
): Promise<void> {
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();
    for (let i = 0; i < ids.length; i++) {
      await conn.execute(
        `UPDATE ${table} SET sort_order = ? WHERE id = ? AND tenant_id = ?`,
        [(i + 1) * 10, ids[i], tenantId]
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

export async function reorderProducts(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { category_id, product_ids } = req.body as z.infer<typeof reorderProductsSchema>;

  // Alle IDs müssen dem Tenant gehören UND in der angegebenen Kategorie liegen
  const placeholders = product_ids.map(() => '?').join(', ');
  const [rows] = await db.execute<any[]>(
    `SELECT id FROM products
     WHERE tenant_id = ? AND category_id <=> ? AND id IN (${placeholders})`,
    [tenantId, category_id, ...product_ids]
  );
  if (rows.length !== product_ids.length) {
    res.status(404).json({ error: 'Produkt nicht gefunden.' });
    return;
  }

  await applyReorder('products', product_ids, tenantId);

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'product.reordered',
    entityType: 'product_category', entityId: category_id ?? 0,
    diff: { new: { category_id, product_ids } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function reorderCategories(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { category_ids } = req.body as z.infer<typeof reorderCategoriesSchema>;

  const placeholders = category_ids.map(() => '?').join(', ');
  const [rows] = await db.execute<any[]>(
    `SELECT id FROM product_categories
     WHERE tenant_id = ? AND is_active = TRUE AND id IN (${placeholders})`,
    [tenantId, ...category_ids]
  );
  if (rows.length !== category_ids.length) {
    res.status(404).json({ error: 'Kategorie nicht gefunden.' });
    return;
  }

  await applyReorder('product_categories', category_ids, tenantId);

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'category.reordered',
    entityType: 'product_category', entityId: category_ids[0],
    diff: { new: { category_ids } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

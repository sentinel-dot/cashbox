import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const createGroupSchema = z.object({
  product_id:     z.number().int().positive().optional(),
  category_id:    z.number().int().positive().optional(),
  name:           z.string().min(1).max(255),
  is_required:    z.boolean(),
  min_selections: z.number().int().nonnegative().default(0),
  max_selections: z.number().int().positive().nullable().optional(),
  sort_order:     z.number().int().nonnegative().optional(),
}).refine(
  d => (d.product_id !== undefined) !== (d.category_id !== undefined),
  { message: 'Entweder product_id ODER category_id angeben — nicht beides, nicht keins.' }
);

export const updateGroupSchema = z.object({
  name:           z.string().min(1).max(255).optional(),
  is_required:    z.boolean().optional(),
  min_selections: z.number().int().nonnegative().optional(),
  max_selections: z.number().int().positive().nullable().optional(),
  sort_order:     z.number().int().nonnegative().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

export const createOptionSchema = z.object({
  name:             z.string().min(1).max(255),
  price_delta_cents: z.number().int().nonnegative(),
  sort_order:       z.number().int().nonnegative().optional(),
});

export const updateOptionSchema = z.object({
  name:             z.string().min(1).max(255).optional(),
  price_delta_cents: z.number().int().nonnegative().optional(),
  sort_order:       z.number().int().nonnegative().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

// ─── Gruppen ─────────────────────────────────────────────────────────────────

export async function listGroups(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

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
     JOIN product_modifier_groups g ON g.id = o.modifier_group_id AND g.tenant_id = ?
     WHERE o.tenant_id = ? AND o.is_active = TRUE
     ORDER BY o.sort_order ASC`,
    [tenantId, tenantId]
  );

  const optionsByGroup = new Map<number, any[]>();
  for (const opt of options) {
    const list = optionsByGroup.get(opt.modifier_group_id) ?? [];
    list.push(opt);
    optionsByGroup.set(opt.modifier_group_id, list);
  }

  res.json(groups.map(g => ({ ...g, options: optionsByGroup.get(g.id) ?? [] })));
}

export async function createGroup(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { product_id, category_id, name, is_required, min_selections, max_selections, sort_order } =
    req.body as z.infer<typeof createGroupSchema>;

  // Produkt/Kategorie-Zugehörigkeit prüfen (Tenant-Isolation)
  if (product_id !== undefined) {
    const [rows] = await db.execute<any[]>(
      'SELECT id FROM products WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
      [product_id, tenantId]
    );
    if (rows.length === 0) { res.status(404).json({ error: 'Produkt nicht gefunden.' }); return; }
  }

  if (category_id !== undefined) {
    const [rows] = await db.execute<any[]>(
      'SELECT id FROM product_categories WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
      [category_id, tenantId]
    );
    if (rows.length === 0) { res.status(404).json({ error: 'Kategorie nicht gefunden.' }); return; }
  }

  const [result] = await db.execute<any>(
    `INSERT INTO product_modifier_groups
       (tenant_id, product_id, category_id, name, is_required, min_selections, max_selections, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [tenantId, product_id ?? null, category_id ?? null, name, is_required,
     min_selections ?? 0, max_selections ?? null, sort_order ?? 0]
  );

  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_group.created',
    entityType: 'modifier_group', entityId: newId,
    diff: { new: { name, product_id, category_id, is_required } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, name, product_id: product_id ?? null, category_id: category_id ?? null,
    is_required, min_selections: min_selections ?? 0, max_selections: max_selections ?? null });
}

export async function updateGroup(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Gruppen-ID.' }); return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id FROM product_modifier_groups WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Modifier-Gruppe nicht gefunden.' }); return; }

  const { name, is_required, min_selections, max_selections, sort_order } =
    req.body as z.infer<typeof updateGroupSchema>;

  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name           !== undefined) { updates.push('name = ?');           values.push(name); }
  if (is_required    !== undefined) { updates.push('is_required = ?');    values.push(is_required); }
  if (min_selections !== undefined) { updates.push('min_selections = ?'); values.push(min_selections); }
  if (max_selections !== undefined) { updates.push('max_selections = ?'); values.push(max_selections); }
  if (sort_order     !== undefined) { updates.push('sort_order = ?');     values.push(sort_order); }

  values.push(targetId, tenantId);
  await db.execute(
    `UPDATE product_modifier_groups SET ${updates.join(', ')} WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_group.updated',
    entityType: 'modifier_group', entityId: targetId,
    diff: { new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function deleteGroup(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Gruppen-ID.' }); return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name FROM product_modifier_groups WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Modifier-Gruppe nicht gefunden.' }); return; }

  // Soft delete: Gruppe + alle Optionen deaktivieren
  await db.execute(
    'UPDATE product_modifier_groups SET is_active = FALSE WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );
  await db.execute(
    'UPDATE product_modifier_options SET is_active = FALSE WHERE modifier_group_id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_group.deleted',
    entityType: 'modifier_group', entityId: targetId,
    diff: { old: { name: rows[0].name } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── Optionen ─────────────────────────────────────────────────────────────────

async function loadGroupForTenant(groupId: number, tenantId: number): Promise<any | null> {
  const [rows] = await db.execute<any[]>(
    'SELECT id FROM product_modifier_groups WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [groupId, tenantId]
  );
  return rows[0] ?? null;
}

export async function createOption(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const groupId  = Number(req.params['id']);
  if (!Number.isInteger(groupId) || groupId <= 0) {
    res.status(400).json({ error: 'Ungültige Gruppen-ID.' }); return;
  }

  // Tenant-Isolation: Gruppe muss zum Tenant gehören
  if (!await loadGroupForTenant(groupId, tenantId)) {
    res.status(404).json({ error: 'Modifier-Gruppe nicht gefunden.' }); return;
  }

  const { name, price_delta_cents, sort_order } = req.body as z.infer<typeof createOptionSchema>;

  const [result] = await db.execute<any>(
    `INSERT INTO product_modifier_options (modifier_group_id, tenant_id, name, price_delta_cents, sort_order)
     VALUES (?, ?, ?, ?, ?)`,
    [groupId, tenantId, name, price_delta_cents, sort_order ?? 0]
  );

  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_option.created',
    entityType: 'modifier_option', entityId: newId,
    diff: { new: { name, price_delta_cents } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, modifier_group_id: groupId, name, price_delta_cents, sort_order: sort_order ?? 0 });
}

export async function updateOption(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const groupId  = Number(req.params['id']);
  const optId    = Number(req.params['optId']);
  if (!Number.isInteger(groupId) || !Number.isInteger(optId) || groupId <= 0 || optId <= 0) {
    res.status(400).json({ error: 'Ungültige ID.' }); return;
  }

  // Tenant-Isolation: Gruppe UND Option müssen zum Tenant gehören
  if (!await loadGroupForTenant(groupId, tenantId)) {
    res.status(404).json({ error: 'Modifier-Gruppe nicht gefunden.' }); return;
  }

  const [optRows] = await db.execute<any[]>(
    'SELECT id FROM product_modifier_options WHERE id = ? AND modifier_group_id = ? AND tenant_id = ? AND is_active = TRUE',
    [optId, groupId, tenantId]
  );
  if (optRows.length === 0) { res.status(404).json({ error: 'Option nicht gefunden.' }); return; }

  const { name, price_delta_cents, sort_order } = req.body as z.infer<typeof updateOptionSchema>;
  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name              !== undefined) { updates.push('name = ?');              values.push(name); }
  if (price_delta_cents !== undefined) { updates.push('price_delta_cents = ?'); values.push(price_delta_cents); }
  if (sort_order        !== undefined) { updates.push('sort_order = ?');        values.push(sort_order); }

  values.push(optId, groupId, tenantId);
  await db.execute(
    `UPDATE product_modifier_options SET ${updates.join(', ')} WHERE id = ? AND modifier_group_id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_option.updated',
    entityType: 'modifier_option', entityId: optId,
    diff: { new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function deleteOption(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const groupId  = Number(req.params['id']);
  const optId    = Number(req.params['optId']);
  if (!Number.isInteger(groupId) || !Number.isInteger(optId) || groupId <= 0 || optId <= 0) {
    res.status(400).json({ error: 'Ungültige ID.' }); return;
  }

  // Tenant-Isolation: Gruppe UND Option prüfen
  if (!await loadGroupForTenant(groupId, tenantId)) {
    res.status(404).json({ error: 'Modifier-Gruppe nicht gefunden.' }); return;
  }

  const [optRows] = await db.execute<any[]>(
    'SELECT id, name FROM product_modifier_options WHERE id = ? AND modifier_group_id = ? AND tenant_id = ? AND is_active = TRUE',
    [optId, groupId, tenantId]
  );
  if (optRows.length === 0) { res.status(404).json({ error: 'Option nicht gefunden.' }); return; }

  await db.execute(
    'UPDATE product_modifier_options SET is_active = FALSE WHERE id = ? AND modifier_group_id = ? AND tenant_id = ?',
    [optId, groupId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'modifier_option.deleted',
    entityType: 'modifier_option', entityId: optId,
    diff: { old: { name: optRows[0].name } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

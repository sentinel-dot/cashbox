import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const createZoneSchema = z.object({
  name:       z.string().min(1).max(255),
  sort_order: z.number().int().nonnegative().optional(),
});

export const updateZoneSchema = z.object({
  name:       z.string().min(1).max(255).optional(),
  sort_order: z.number().int().nonnegative().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

export const createTableSchema = z.object({
  name:       z.string().min(1).max(255),
  zone_id:    z.number().int().positive().optional(),
  sort_order: z.number().int().nonnegative().optional(),
});

export const updateTableSchema = z.object({
  name:      z.string().min(1).max(255).optional(),
  zone_id:   z.number().int().positive().nullable().optional(),
  is_active: z.boolean().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

// ─── Zonen ───────────────────────────────────────────────────────────────────

export async function listZones(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const [rows] = await db.execute<any[]>(
    `SELECT id, name, sort_order
     FROM zones
     WHERE tenant_id = ?
     ORDER BY sort_order ASC, name ASC`,
    [tenantId]
  );
  res.json(rows);
}

export async function createZone(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { name, sort_order } = req.body as z.infer<typeof createZoneSchema>;

  const [result] = await db.execute<any>(
    `INSERT INTO zones (tenant_id, name, sort_order) VALUES (?, ?, ?)`,
    [tenantId, name, sort_order ?? 0]
  );
  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'zone.created',
    entityType: 'zone', entityId: newId,
    diff: { new: { name, sort_order } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, name, sort_order: sort_order ?? 0 });
}

export async function updateZone(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Zonen-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, sort_order FROM zones WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Zone nicht gefunden.' }); return; }

  const { name, sort_order } = req.body as z.infer<typeof updateZoneSchema>;
  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name       !== undefined) { updates.push('name = ?');       values.push(name); }
  if (sort_order !== undefined) { updates.push('sort_order = ?'); values.push(sort_order); }

  values.push(targetId, tenantId);
  await db.execute(
    `UPDATE zones SET ${updates.join(', ')} WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'zone.updated',
    entityType: 'zone', entityId: targetId,
    diff: { old: rows[0], new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

// ─── Tische ──────────────────────────────────────────────────────────────────

export async function listTables(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  // Tische inkl. Zone + offene Order (falls vorhanden)
  const [rows] = await db.execute<any[]>(
    `SELECT
       t.id, t.name, t.is_active,
       z.id   AS zone_id,
       z.name AS zone_name,
       z.sort_order AS zone_sort_order,
       (SELECT COUNT(*) FROM orders o
        WHERE o.table_id = t.id
          AND o.tenant_id = ?
          AND o.status = 'open') AS open_orders_count
     FROM tables t
     LEFT JOIN zones z ON z.id = t.zone_id AND z.tenant_id = ?
     WHERE t.tenant_id = ? AND t.is_active = TRUE
     ORDER BY z.sort_order ASC, z.name ASC, t.name ASC`,
    [tenantId, tenantId, tenantId]
  );

  const result = rows.map(r => ({
    id:         r.id,
    name:       r.name,
    is_active:  r.is_active,
    open_orders_count: Number(r.open_orders_count),
    zone: r.zone_id ? { id: r.zone_id, name: r.zone_name, sort_order: r.zone_sort_order } : null,
  }));

  res.json(result);
}

export async function createTable(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const { name, zone_id } = req.body as z.infer<typeof createTableSchema>;

  // Zone-Zugehörigkeit prüfen
  if (zone_id !== undefined) {
    const [zoneRows] = await db.execute<any[]>(
      'SELECT id FROM zones WHERE id = ? AND tenant_id = ?',
      [zone_id, tenantId]
    );
    if (zoneRows.length === 0) {
      res.status(404).json({ error: 'Zone nicht gefunden.' });
      return;
    }
  }

  const [result] = await db.execute<any>(
    `INSERT INTO tables (tenant_id, zone_id, name) VALUES (?, ?, ?)`,
    [tenantId, zone_id ?? null, name]
  );
  const newId = result.insertId as number;

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'table.created',
    entityType: 'table', entityId: newId,
    diff: { new: { name, zone_id } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.status(201).json({ id: newId, name, zone_id: zone_id ?? null });
}

export async function updateTable(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Tisch-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, zone_id, is_active FROM tables WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Tisch nicht gefunden.' }); return; }

  const { name, zone_id, is_active } = req.body as z.infer<typeof updateTableSchema>;

  // Zone-Zugehörigkeit prüfen wenn gesetzt
  if (zone_id !== undefined && zone_id !== null) {
    const [zoneRows] = await db.execute<any[]>(
      'SELECT id FROM zones WHERE id = ? AND tenant_id = ?',
      [zone_id, tenantId]
    );
    if (zoneRows.length === 0) {
      res.status(404).json({ error: 'Zone nicht gefunden.' });
      return;
    }
  }

  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name      !== undefined) { updates.push('name = ?');      values.push(name); }
  if (zone_id   !== undefined) { updates.push('zone_id = ?');   values.push(zone_id); }
  if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active); }

  values.push(targetId, tenantId);
  await db.execute(
    `UPDATE tables SET ${updates.join(', ')} WHERE id = ? AND tenant_id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'table.updated',
    entityType: 'table', entityId: targetId,
    diff: { old: rows[0], new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

export async function deleteTable(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const targetId = Number(req.params['id']);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ error: 'Ungültige Tisch-ID.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name FROM tables WHERE id = ? AND tenant_id = ? AND is_active = TRUE',
    [targetId, tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Tisch nicht gefunden.' }); return; }

  // Nicht löschen wenn offene Orders vorhanden
  const [openOrders] = await db.execute<any[]>(
    `SELECT COUNT(*) AS cnt FROM orders WHERE table_id = ? AND tenant_id = ? AND status = 'open'`,
    [targetId, tenantId]
  );
  if (Number(openOrders[0].cnt) > 0) {
    res.status(409).json({ error: 'Tisch hat noch offene Bestellungen.' });
    return;
  }

  await db.execute(
    'UPDATE tables SET is_active = FALSE WHERE id = ? AND tenant_id = ?',
    [targetId, tenantId]
  );

  await writeAuditLog({
    tenantId, userId: req.auth!.userId, action: 'table.deleted',
    entityType: 'table', entityId: targetId,
    diff: { old: { name: rows[0].name } },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Schemas ─────────────────────────────────────────────────────────────────

export const updateTenantSchema = z.object({
  name:        z.string().min(1).max(255).optional(),
  address:     z.string().min(1).optional(),
  vat_id:      z.string().min(1).max(50).nullable().optional(),
  tax_number:  z.string().min(1).max(50).nullable().optional(),
}).refine(d => Object.keys(d).length > 0, { message: 'Mindestens ein Feld erforderlich.' });

// ─── GET /tenants/me ──────────────────────────────────────────────────────────

export async function getTenant(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;

  const [rows] = await db.execute<any[]>(
    `SELECT id, name, address, vat_id, tax_number, plan, subscription_status, created_at
     FROM tenants WHERE id = ?`,
    [tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Tenant nicht gefunden.' }); return; }

  res.json(rows[0]);
}

// ─── PATCH /tenants/me ────────────────────────────────────────────────────────
// Nur owner darf Tenant-Daten ändern (Bon-Pflichtfelder: Adresse, Steuernummer)

export async function updateTenant(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;

  if (req.auth!.role !== 'owner') {
    res.status(403).json({ error: 'Nur Owner dürfen Tenant-Stammdaten ändern.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, name, address, vat_id, tax_number FROM tenants WHERE id = ?',
    [tenantId]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Tenant nicht gefunden.' }); return; }

  const { name, address, vat_id, tax_number } = req.body as z.infer<typeof updateTenantSchema>;
  const updates: string[] = [];
  const values:  unknown[] = [];

  if (name       !== undefined) { updates.push('name = ?');       values.push(name); }
  if (address    !== undefined) { updates.push('address = ?');    values.push(address); }
  if (vat_id     !== undefined) { updates.push('vat_id = ?');     values.push(vat_id); }
  if (tax_number !== undefined) { updates.push('tax_number = ?'); values.push(tax_number); }

  values.push(tenantId);
  await db.execute(
    `UPDATE tenants SET ${updates.join(', ')} WHERE id = ?`,
    values as any[]
  );

  await writeAuditLog({
    tenantId, userId, action: 'tenant.updated',
    entityType: 'tenant', entityId: tenantId,
    diff: { old: rows[0], new: req.body },
    ipAddress: req.ip, deviceId: req.auth!.deviceId,
  });

  res.json({ ok: true });
}

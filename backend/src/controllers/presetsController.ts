// presetsController.ts — S17B: Starter-Sortimente lesen + idempotent importieren.
// Vertrag: docs/s17-sortiment-starterpakete.md §8. Der Server validiert jede
// Zeile gegen SEINE Preset-Definition — vom Client erfundene Zeilen werden
// abgewiesen. Änderbar sind nur Name, Preis, bestätigte Sätze, Auswahl, Visual.

import { Request, Response } from 'express';
import { z } from 'zod';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';
import { createProductWithHistory } from '../services/products.js';
import { ALL_PRESETS, getPreset } from '../services/presets/presetData.js';
import {
  VISUAL_KEYS, COLOR_ROLE_HEX, TAX_BASIS_VERSION, AssortmentPreset,
} from '../services/presets/presetTypes.js';
import { PLAN_LIMITS, Plan } from '../middleware/planMiddleware.js';

// Nach dieser Zeit gilt ein 'processing'-Import als abgestürzt und darf von
// einem Retry mit demselben Idempotency-Key übernommen werden (analog zum
// Stuck-Claim-Reset der offline_queue/email_queue).
const STALE_PROCESSING_MS = 2 * 60 * 1000;

// ─── Schemas ─────────────────────────────────────────────────────────────────

export const importPresetSchema = z.object({
  preset_id:         z.enum(['shisha_bar', 'cafe', 'spaeti', 'empty']),
  preset_version:    z.literal(1),
  tax_basis_version: z.literal(TAX_BASIS_VERSION),
  // §2.3: auch grüne Standardzeilen werden nie still übernommen
  vat_confirmed:     z.literal(true),
  items: z.array(z.object({
    item_key:          z.string().min(1).max(64),
    name:              z.string().min(1).max(255),
    price_cents:       z.number().int().positive(),   // 0,00 € ist nie zulässig (§1.2)
    vat_rate_inhouse:  z.enum(['7', '19']),
    vat_rate_takeaway: z.enum(['7', '19']),
    visual_key:        z.enum(VISUAL_KEYS).nullable(),
    review_confirmed:  z.boolean().optional(),
    on_name_collision: z.enum(['skip', 'create']).optional(),
  })).min(1).max(100),
});

type ImportBody = z.infer<typeof importPresetSchema>;
type ImportItem = ImportBody['items'][number];

interface SkippedItem { item_key: string; reason: 'name_collision' | 'already_imported' }

// ─── GET /products/presets ───────────────────────────────────────────────────
// Presets sind global/statisch — lesbar für alle authentifizierten Rollen (§8.4)

export async function listPresets(_req: Request, res: Response): Promise<void> {
  res.json(ALL_PRESETS.map(preset => ({
    ...preset,
    categories: preset.categories.map(c => ({ ...c, color: COLOR_ROLE_HEX[c.color_role] })),
  })));
}

// ─── POST /products/presets/import ───────────────────────────────────────────

export async function importPreset(req: Request, res: Response): Promise<void> {
  const tenantId = req.auth!.tenantId;
  const userId   = req.auth!.userId;
  const body     = req.body as ImportBody;

  // Idempotency-Key: UUID im Header, Pflicht
  const keyParse = z.string().uuid().safeParse(req.header('Idempotency-Key'));
  if (!keyParse.success) {
    res.status(400).json({ error: 'Header Idempotency-Key (UUID) ist erforderlich.' });
    return;
  }
  const idempotencyKey = keyParse.data;

  const preset = getPreset(body.preset_id, body.preset_version);
  if (!preset) {
    res.status(400).json({ error: 'Unbekanntes Preset oder falsche Version.' });
    return;
  }

  // ── Serverseitige Re-Validierung gegen die eigene Definition ──
  const validationError = validateItems(body.items, preset);
  if (validationError) {
    res.status(400).json(validationError);
    return;
  }

  // ── Plan-Limit für den Bulk (Middleware prüft nur +1) ──
  const limitError = await checkPlanLimit(tenantId, body.items.length);
  if (limitError) {
    res.status(403).json(limitError);
    return;
  }

  // ── Idempotenz-Anker beanspruchen (stripe_events-Muster) ──
  const claim = await claimImport(tenantId, idempotencyKey, body, userId);
  if (claim.type === 'replay') {
    res.status(200).json(claim.result);
    return;
  }
  if (claim.type === 'busy') {
    res.status(409).json({ error: 'Import läuft bereits. Bitte kurz warten und erneut versuchen.' });
    return;
  }
  const importId = claim.importId;

  try {
    // ── Kategorien: find-or-create per Herkunft ──
    const neededCatKeys = new Set(
      body.items.map(item => preset.products.find(p => p.item_key === item.item_key)!.category_key)
    );
    const categoryIds = new Map<string, number>();
    let categoriesCreated = 0;

    // Bestehende Kategorien nicht verdrängen: Preset-Reihenfolge hinter das
    // vorhandene Maximum hängen (frischer Tenant: Basis 0 ⇒ exakt Preset-Ordnung)
    const [maxCatRows] = await db.execute<any[]>(
      'SELECT COALESCE(MAX(sort_order), 0) AS max_sort FROM product_categories WHERE tenant_id = ? AND is_active = TRUE',
      [tenantId]
    );
    const catSortBase = maxCatRows[0].max_sort as number;

    for (const catDef of preset.categories) {
      if (!neededCatKeys.has(catDef.category_key)) continue;
      const { id, created } = await findOrCreateCategory(tenantId, preset, catDef.category_key, catSortBase);
      categoryIds.set(catDef.category_key, id);
      if (created) categoriesCreated++;
    }

    // ── Produkte über den gemeinsamen GoBD-Service ──
    let productsImported = 0;
    const skipped: SkippedItem[] = [];

    for (const item of body.items) {
      const def = preset.products.find(p => p.item_key === item.item_key)!;

      // Namenskollision mit fremden (nicht selbst importierten) aktiven Produkten
      const [collision] = await db.execute<any[]>(
        `SELECT id FROM products
         WHERE tenant_id = ? AND is_active = TRUE AND name = ?
           AND NOT (origin_preset_id <=> ? AND origin_item_key <=> ?)`,
        [tenantId, item.name, preset.preset_id, item.item_key]
      );
      if (collision.length > 0 && (item.on_name_collision ?? 'skip') === 'skip') {
        skipped.push({ item_key: item.item_key, reason: 'name_collision' });
        continue;
      }

      const result = await createProductWithHistory({
        tenantId,
        userId,
        name:            item.name,
        categoryId:      categoryIds.get(def.category_key) ?? null,
        priceCents:      item.price_cents,
        vatRateInhouse:  item.vat_rate_inhouse,
        vatRateTakeaway: item.vat_rate_takeaway,
        sortOrder:       def.sort_order,
        visualKey:       item.visual_key,
        origin: {
          presetId:      preset.preset_id,
          presetVersion: preset.version,
          itemKey:       item.item_key,
        },
      });

      if (result.status === 'exists') {
        skipped.push({ item_key: item.item_key, reason: 'already_imported' });
      } else {
        productsImported++;
      }
    }

    const importResult = {
      import_id: importId,
      imported:  { categories: categoriesCreated, products: productsImported },
      skipped,
    };

    await db.execute(
      `UPDATE preset_imports
       SET status = 'completed', result_json = ?, completed_at = NOW()
       WHERE id = ? AND tenant_id = ?`,
      [JSON.stringify(importResult), importId, tenantId]
    );

    // §8.3.6: Audit-Snapshot mit Preset, Steuerbasis, bestätigenden Nutzer + Werten
    await writeAuditLog({
      tenantId, userId, action: 'preset.imported',
      entityType: 'preset_import', entityId: importId,
      diff: {
        new: {
          preset_id: preset.preset_id,
          preset_version: preset.version,
          tax_basis_version: preset.tax_basis_version,
          vat_confirmed: true,
          items: body.items,
          result: importResult,
        },
      },
      ipAddress: req.ip, deviceId: req.auth!.deviceId,
    });

    res.status(201).json(importResult);
  } catch (err) {
    // Retry mit demselben Idempotency-Key darf übernehmen; der Service
    // repariert halb angelegte (inaktive) Produkte statt sie zu duplizieren
    await db.execute(
      `UPDATE preset_imports SET status = 'failed' WHERE id = ? AND tenant_id = ?`,
      [importId, tenantId]
    );
    throw err;
  }
}

// ─── Validierung (§2.3, §5.3, §5.4, §8.1) ────────────────────────────────────

function validateItems(
  items: ImportItem[], preset: AssortmentPreset
): { error: string; code?: string; item_keys?: string[] } | null {
  const seen = new Set<string>();
  const depositBlocked: string[] = [];

  for (const item of items) {
    if (seen.has(item.item_key)) {
      return { error: `item_key '${item.item_key}' ist doppelt.` };
    }
    seen.add(item.item_key);

    const def = preset.products.find(p => p.item_key === item.item_key);
    if (!def) {
      return { error: `Unbekannter item_key '${item.item_key}' für dieses Preset.` };
    }

    // §5.4: Pfand-Gate — serverseitig, nicht nur UI
    if (def.deposit_cents === 25) {
      depositBlocked.push(item.item_key);
      continue;
    }

    switch (def.vat_review) {
      case 'standard_19':
      case 'food_7_2026':
        // Vorschlag ist bestätigungspflichtig, aber nicht frei änderbar
        if (
          item.vat_rate_inhouse !== def.vat_rate_inhouse ||
          item.vat_rate_takeaway !== def.vat_rate_takeaway
        ) {
          return {
            error: `MwSt.-Satz für '${item.item_key}' weicht vom Preset-Vorschlag ab. Standard- und Speisenzeilen sind nicht frei änderbar.`,
          };
        }
        break;
      case 'recipe_review':
      case 'printed_price_review':
        // §2.3: nie über eine globale „Alles bestätigen"-Aktion erledigen
        if (item.review_confirmed !== true) {
          return {
            error: `'${item.item_key}' erfordert eine Einzelbestätigung (review_confirmed).`,
            code: 'review_required',
            item_keys: [item.item_key],
          };
        }
        break;
    }

    // §5.3: Tabakvorlagen nur mit konkretem eigenem Namen
    if (def.requires_custom_name) {
      const trimmed = item.name.trim();
      if (trimmed.length === 0 || trimmed === def.name_de) {
        return {
          error: `'${item.item_key}' ist eine Vorlage: bitte konkreten Produktnamen ([Marke] [Variante], [Menge]) angeben.`,
          code: 'custom_name_required',
          item_keys: [item.item_key],
        };
      }
    }
  }

  if (depositBlocked.length > 0) {
    return {
      error: 'Pfandfunktion erforderlich — pfandpflichtige Artikel können noch nicht importiert werden.',
      code: 'deposit_gate',
      item_keys: depositBlocked,
    };
  }

  return null;
}

// ─── Plan-Limit (Bulk) ───────────────────────────────────────────────────────

async function checkPlanLimit(
  tenantId: number, itemCount: number
): Promise<{ error: string; limit: number; current: number; plan: string } | null> {
  const [tenantRows] = await db.execute<any[]>(
    'SELECT plan FROM tenants WHERE id = ?', [tenantId]
  );
  const plan = (tenantRows[0]?.plan ?? 'starter') as Plan;
  const limit = PLAN_LIMITS[plan]?.products ?? 0;
  if (limit === Infinity) return null;

  const [countRows] = await db.execute<any[]>(
    'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ? AND is_active = TRUE',
    [tenantId]
  );
  const current = countRows[0]?.cnt ?? 0;
  if (current + itemCount > limit) {
    return {
      error: `Plan-Limit erreicht: products (${current} + ${itemCount} Import > ${limit}). Upgrade erforderlich.`,
      limit, current, plan,
    };
  }
  return null;
}

// ─── Idempotenz-Anker ────────────────────────────────────────────────────────

type ClaimResult =
  | { type: 'proceed'; importId: number }
  | { type: 'replay'; result: unknown }
  | { type: 'busy' };

async function claimImport(
  tenantId: number, idempotencyKey: string, body: ImportBody, userId: number
): Promise<ClaimResult> {
  try {
    const [result] = await db.execute<any>(
      `INSERT INTO preset_imports
         (tenant_id, idempotency_key, preset_id, preset_version, tax_basis_version, requested_by_user_id)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [tenantId, idempotencyKey, body.preset_id, body.preset_version, body.tax_basis_version, userId]
    );
    return { type: 'proceed', importId: result.insertId as number };
  } catch (err: unknown) {
    if (!(typeof err === 'object' && err !== null && (err as { code?: string }).code === 'ER_DUP_ENTRY')) {
      throw err;
    }
  }

  const [rows] = await db.execute<any[]>(
    `SELECT id, status, result_json, created_at FROM preset_imports
     WHERE tenant_id = ? AND idempotency_key = ?`,
    [tenantId, idempotencyKey]
  );
  const row = rows[0];
  if (!row) return { type: 'busy' };   // Race beim Aufräumen — Client soll erneut versuchen

  if (row.status === 'completed') {
    const stored = typeof row.result_json === 'string' ? JSON.parse(row.result_json) : row.result_json;
    return { type: 'replay', result: stored };
  }

  // 'failed' oder abgestürztes 'processing' übernehmen — atomar, damit von zwei
  // parallelen Retries nur einer weiterarbeitet
  const [takeover] = await db.execute<any>(
    `UPDATE preset_imports
     SET status = 'processing', created_at = NOW()
     WHERE id = ? AND tenant_id = ?
       AND (status = 'failed' OR (status = 'processing' AND created_at < NOW() - INTERVAL ? SECOND))`,
    [row.id, tenantId, Math.floor(STALE_PROCESSING_MS / 1000)]
  );
  if (takeover.affectedRows === 1) {
    return { type: 'proceed', importId: row.id as number };
  }
  return { type: 'busy' };
}

// ─── Kategorien find-or-create ───────────────────────────────────────────────

async function findOrCreateCategory(
  tenantId: number, preset: AssortmentPreset, categoryKey: string, sortBase: number
): Promise<{ id: number; created: boolean }> {
  const catDef = preset.categories.find(c => c.category_key === categoryKey)!;

  const select = async (): Promise<number | null> => {
    const [rows] = await db.execute<any[]>(
      `SELECT id FROM product_categories
       WHERE tenant_id = ? AND origin_preset_id = ? AND origin_category_key = ?`,
      [tenantId, preset.preset_id, categoryKey]
    );
    return rows.length > 0 ? (rows[0].id as number) : null;
  };

  const existing = await select();
  if (existing !== null) return { id: existing, created: false };

  try {
    const [result] = await db.execute<any>(
      `INSERT INTO product_categories
         (tenant_id, name, color, sort_order, origin_preset_id, origin_preset_version, origin_category_key)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        tenantId, catDef.name_de, COLOR_ROLE_HEX[catDef.color_role],
        sortBase + catDef.sort_order,
        preset.preset_id, preset.version, categoryKey,
      ]
    );
    return { id: result.insertId as number, created: true };
  } catch (err: unknown) {
    // Paralleler Import: UNIQUE (tenant, preset, category_key) — Gewinner übernehmen
    if (typeof err === 'object' && err !== null && (err as { code?: string }).code === 'ER_DUP_ENTRY') {
      const raced = await select();
      if (raced !== null) return { id: raced, created: false };
    }
    throw err;
  }
}

// services/products.ts — S17B: der EINE GoBD-konforme Produktanlage-Pfad.
// Controller (POST /products) und Preset-Import teilen sich diese Funktion —
// es gibt bewusst keinen zweiten Produkt-INSERT im Code (Spec §8.3).
//
// Warum kein einfaches "INSERT + History": product_price_history wird über den
// separaten INSERT-only-User (auditDb) geschrieben — eine gemeinsame Transaktion
// über beide Pools ist unmöglich. Deshalb gilt der robuste Ablauf:
//   1. Produkt INAKTIV anlegen (oder per Herkunft finden)
//   2. Initialen History-Eintrag via auditDb schreiben
//   3. Existenz + exakte Werte des History-Eintrags verifizieren (db-Pool)
//   4. Erst danach aktivieren
// Schlägt irgendetwas dazwischen fehl, bleibt das Produkt inaktiv und damit
// niemals verkaufsfähig ohne Historie. Ein Retry mit Herkunft (Preset) repariert
// denselben Datensatz statt einen zweiten anzulegen; ein Retry ohne Herkunft
// (manuelles POST /products) legt ein frisches Produkt an — der inaktive Rest
// ist harmlos und im Sortiment unter „Inaktiv" sichtbar.

import { db } from '../db/index.js';
import { writePriceHistory } from './priceHistory.js';

export interface CreateProductInput {
  tenantId:        number;
  userId:          number;
  name:            string;
  categoryId:      number | null;
  priceCents:      number;
  vatRateInhouse:  '7' | '19';
  vatRateTakeaway: '7' | '19';
  sortOrder:       number;
  visualKey:       string | null;
  origin?: {
    presetId:      string;
    presetVersion: number;
    itemKey:       string;
  };
}

export type CreateProductResult =
  | { status: 'created' | 'repaired'; id: number }
  // Herkunfts-Zeile existiert bereits mit gültiger Historie (aktiv ODER vom
  // Betreiber bewusst deaktiviert) — niemals überschreiben oder reaktivieren
  | { status: 'exists'; id: number };

interface OriginRow { id: number; is_active: number }

export async function createProductWithHistory(
  input: CreateProductInput
): Promise<CreateProductResult> {
  const { tenantId, origin } = input;

  let productId: number | null = null;
  let isRepair = false;

  if (origin) {
    const existing = await findByOrigin(tenantId, origin.presetId, origin.itemKey);
    if (existing) {
      const resolved = await resolveExisting(existing, tenantId);
      if (resolved) return resolved;
      // inaktiv OHNE Historie = abgebrochener früherer Import → reparieren
      productId = existing.id;
      isRepair = true;
    }
  }

  if (productId === null) {
    try {
      const [result] = await db.execute<any>(
        `INSERT INTO products
           (tenant_id, category_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway,
            sort_order, visual_key, is_active,
            origin_preset_id, origin_preset_version, origin_item_key)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, FALSE, ?, ?, ?)`,
        [
          tenantId, input.categoryId, input.name, input.priceCents,
          input.vatRateInhouse, input.vatRateTakeaway,
          input.sortOrder, input.visualKey,
          origin?.presetId ?? null, origin?.presetVersion ?? null, origin?.itemKey ?? null,
        ]
      );
      productId = result.insertId as number;
    } catch (err: unknown) {
      // Paralleler Doppeltap: UNIQUE (tenant, preset, item_key) hat gegriffen —
      // die Zeile des Gewinners übernehmen und wie ein gefundener Datensatz behandeln
      if (origin && isDupEntry(err)) {
        const existing = await findByOrigin(tenantId, origin.presetId, origin.itemKey);
        if (existing) {
          const resolved = await resolveExisting(existing, tenantId);
          if (resolved) return resolved;
          productId = existing.id;
          isRepair = true;
        } else {
          throw err;
        }
      } else {
        throw err;
      }
    }
  }

  // 2. GoBD: initialer History-Eintrag (INSERT-only via auditDb)
  await writePriceHistory({
    productId,
    tenantId,
    priceCents:      input.priceCents,
    vatRateInhouse:  input.vatRateInhouse,
    vatRateTakeaway: input.vatRateTakeaway,
    changedByUserId: input.userId,
  });

  // 3. Verifizieren: die letzte History-Zeile muss exakt unseren Werten entsprechen
  const [histRows] = await db.execute<any[]>(
    `SELECT price_cents, vat_rate_inhouse, vat_rate_takeaway
     FROM product_price_history
     WHERE product_id = ? AND tenant_id = ?
     ORDER BY id DESC LIMIT 1`,
    [productId, tenantId]
  );
  const hist = histRows[0];
  if (
    !hist ||
    hist.price_cents !== input.priceCents ||
    hist.vat_rate_inhouse !== input.vatRateInhouse ||
    hist.vat_rate_takeaway !== input.vatRateTakeaway
  ) {
    // Produkt bleibt inaktiv — nie verkaufsfähig ohne verifizierte Historie
    throw new Error(
      `Preis-Historie für Produkt ${productId} konnte nicht verifiziert werden — Produkt bleibt inaktiv.`
    );
  }

  // 4. Aktivieren
  await db.execute(
    'UPDATE products SET is_active = TRUE, updated_at = NOW() WHERE id = ? AND tenant_id = ?',
    [productId, tenantId]
  );

  return { status: isRepair ? 'repaired' : 'created', id: productId };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async function findByOrigin(
  tenantId: number, presetId: string, itemKey: string
): Promise<OriginRow | null> {
  const [rows] = await db.execute<any[]>(
    `SELECT id, is_active FROM products
     WHERE tenant_id = ? AND origin_preset_id = ? AND origin_item_key = ?`,
    [tenantId, presetId, itemKey]
  );
  return rows.length > 0 ? (rows[0] as OriginRow) : null;
}

/**
 * Entscheidet, ob eine vorhandene Herkunfts-Zeile unangetastet bleibt:
 * - aktiv → exists (Betreiberdaten gewinnen immer)
 * - inaktiv MIT History-Eintrag → exists (der Betreiber hat sie bewusst
 *   deaktiviert — ein Re-Import darf sie NICHT still reaktivieren)
 * - inaktiv OHNE History → null (abgebrochener Import, Repair erlaubt)
 */
async function resolveExisting(
  existing: OriginRow, tenantId: number
): Promise<CreateProductResult | null> {
  if (existing.is_active) return { status: 'exists', id: existing.id };

  const [histCount] = await db.execute<any[]>(
    'SELECT COUNT(*) AS cnt FROM product_price_history WHERE product_id = ? AND tenant_id = ?',
    [existing.id, tenantId]
  );
  if (histCount[0].cnt > 0) return { status: 'exists', id: existing.id };
  return null;
}

function isDupEntry(err: unknown): boolean {
  return (
    typeof err === 'object' && err !== null &&
    'code' in err && (err as { code?: string }).code === 'ER_DUP_ENTRY'
  );
}

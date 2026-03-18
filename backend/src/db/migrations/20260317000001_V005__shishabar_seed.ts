import { Connection } from 'mysql2/promise';
import bcrypt from 'bcrypt';

// ─── Shishabar Pilot Seed Data ───────────────────────────────────────────────
//
// Testdaten für Shisha Lounge Berlin (Pilotkunde).
// Nur für dev/test — kein Produktions-Guard, da es keine Finanzdaten sind.
//
// Login:   niko@shishalounge.de / pilot2024
// PINs:    Niko=1234, Sara=2222, Max=3333, Lena=4444
// Device-Token (Dev-iPad): shishabar-dev-ipad-token-2026
// ─────────────────────────────────────────────────────────────────────────────

export async function up(db: Connection): Promise<void> {

  // ─── Passwort- und PIN-Hashes ────────────────────────────────────────────
  const COST = 10;
  const pwHash  = await bcrypt.hash('pilot2024', COST);
  const pin1234 = await bcrypt.hash('1234', COST);
  const pin2222 = await bcrypt.hash('2222', COST);
  const pin3333 = await bcrypt.hash('3333', COST);
  const pin4444 = await bcrypt.hash('4444', COST);
  // Device-Token: SHA2-Hash wie im authController (findDeviceByToken nutzt SHA2(?, 256))
  // Bcrypt wäre hier falsch — Tokens werden NICHT mit bcrypt verglichen!

  // ─── Tenant ──────────────────────────────────────────────────────────────
  const [tenantResult] = await db.execute<any>(
    `INSERT INTO tenants
       (name, address, tax_number, plan, subscription_status, created_at)
     VALUES (?, ?, ?, 'pro', 'active', NOW())`,
    [
      'Shisha Lounge Berlin',
      'Kurfürstendamm 42, 10707 Berlin',
      '30/123/45678',
    ]
  );
  const tenantId: number = tenantResult.insertId;

  // ─── Users ───────────────────────────────────────────────────────────────
  const [ownerResult] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash, is_active)
     VALUES (?, ?, ?, ?, 'owner', ?, TRUE)`,
    [tenantId, 'Niko Müller', 'niko@shishalounge.de', pwHash, pin1234]
  );
  const ownerId: number = ownerResult.insertId;

  await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash, is_active)
     VALUES (?, ?, ?, ?, 'manager', ?, TRUE)`,
    [tenantId, 'Sara König', 'sara@shishalounge.de', pwHash, pin2222]
  );
  await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash, is_active)
     VALUES (?, ?, ?, ?, 'staff', ?, TRUE)`,
    [tenantId, 'Max Berger', 'max@shishalounge.de', pwHash, pin3333]
  );
  await db.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, pin_hash, is_active)
     VALUES (?, ?, ?, ?, 'staff', ?, TRUE)`,
    [tenantId, 'Lena Wolf', 'lena@shishalounge.de', pwHash, pin4444]
  );

  // ─── Dev-Device ──────────────────────────────────────────────────────────
  // Token-Klartext: shishabar-dev-ipad-token-2026
  // iOS-App nutzt diesen Token im DEBUG-Build (siehe APIClient.swift deviceTokenOrCreate)
  // Hash wird via SQL SHA2() berechnet — exakt wie findDeviceByToken im authController
  await db.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash, is_revoked, last_seen_at)
     VALUES (?, 'Dev-iPad (Seed)', SHA2('shishabar-dev-ipad-token-2026', 256), FALSE, NOW())`,
    [tenantId]
  );

  // ─── Produktkategorien ───────────────────────────────────────────────────
  const [catShisha]  = await db.execute<any>(
    `INSERT INTO product_categories (tenant_id, name, color, sort_order, is_active) VALUES (?, 'Shisha', '#8e44ad', 0, TRUE)`,
    [tenantId]
  );
  const [catGetraenk] = await db.execute<any>(
    `INSERT INTO product_categories (tenant_id, name, color, sort_order, is_active) VALUES (?, 'Getränke', '#2980b9', 1, TRUE)`,
    [tenantId]
  );
  const [catSnacks]  = await db.execute<any>(
    `INSERT INTO product_categories (tenant_id, name, color, sort_order, is_active) VALUES (?, 'Snacks & Speisen', '#27ae60', 2, TRUE)`,
    [tenantId]
  );
  const [catTabak]   = await db.execute<any>(
    `INSERT INTO product_categories (tenant_id, name, color, sort_order, is_active) VALUES (?, 'Tabak & Zubehör', '#e67e22', 3, TRUE)`,
    [tenantId]
  );

  const catShishaId   = catShisha.insertId   as number;
  const catGetraenkId = catGetraenk.insertId as number;
  const catSnacksId   = catSnacks.insertId   as number;
  const catTabakId    = catTabak.insertId    as number;

  // ─── Produkte ────────────────────────────────────────────────────────────
  // Alle Produkte 19% MwSt (Shisha-Bar Inhouse — Tabak + Getränke)
  // price_cents + vat_rate_* sind IMMUTABLE nach dem INSERT (GoBD — keine updates)

  // Shisha
  const shishaProducts = [
    ['Shisha Double Apple',    1800, catShishaId],
    ['Shisha Blueberry',       1800, catShishaId],
    ['Shisha Watermelon Mint', 2000, catShishaId],
    ['Shisha Special Mix',     2500, catShishaId],
    ['Shisha Nachfüllung',     1000, catShishaId],
  ];
  // Getränke
  const getraenkeProducts = [
    ['Cola',           350, catGetraenkId],
    ['Wasser',         250, catGetraenkId],
    ['Energydrink',    400, catGetraenkId],
    ['Tee',            300, catGetraenkId],
    ['Latte Macchiato',450, catGetraenkId],
    ['Fanta',          350, catGetraenkId],
    ['Saft',           380, catGetraenkId],
  ];
  // Snacks
  const snacksProducts = [
    ['Nachos mit Dip', 650, catSnacksId],
    ['Chips',          350, catSnacksId],
    ['Mixed Nuts',     400, catSnacksId],
  ];
  // Tabak & Zubehör
  const tabakProducts = [
    ['Tabak Dose',   2000, catTabakId],
    ['Kohle-Set',     500, catTabakId],
    ['Zubehör-Pack', 1200, catTabakId],
  ];

  const allProducts = [
    ...shishaProducts,
    ...getraenkeProducts,
    ...snacksProducts,
    ...tabakProducts,
  ];

  for (const [name, priceCents, categoryId] of allProducts) {
    await db.execute(
      `INSERT INTO products
         (tenant_id, category_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway, is_active)
       VALUES (?, ?, ?, ?, '19', '19', TRUE)`,
      [tenantId, categoryId, name, priceCents]
    );
  }

  // ─── Modifier-Gruppe für Shisha: Tabaksorte (Pflicht, Einfachauswahl) ────
  const [mgResult] = await db.execute<any>(
    `INSERT INTO product_modifier_groups
       (tenant_id, category_id, product_id, name, is_required, min_selections, max_selections, is_active, sort_order)
     VALUES (?, ?, NULL, 'Tabaksorte', TRUE, 1, 1, TRUE, 0)`,
    [tenantId, catShishaId]
  );
  const mgId: number = mgResult.insertId;

  const tabakSorten = [
    ['Al Fakher',        0, 0],
    ['Adalya',           0, 1],
    ['Darkside',       200, 2],  // Premium +2€
    ['Social Smoke',   200, 3],  // Premium +2€
    ['Burn',             0, 4],
  ];
  for (const [name, delta, sortOrder] of tabakSorten) {
    await db.execute(
      `INSERT INTO product_modifier_options
         (modifier_group_id, tenant_id, name, price_delta_cents, is_active, sort_order)
       VALUES (?, ?, ?, ?, TRUE, ?)`,
      [mgId, tenantId, name, delta, sortOrder]
    );
  }

  // ─── Zonen ───────────────────────────────────────────────────────────────
  const [zoneInnenResult] = await db.execute<any>(
    `INSERT INTO zones (tenant_id, name, sort_order) VALUES (?, 'Innen', 0)`,
    [tenantId]
  );
  const [zoneLoungeResult] = await db.execute<any>(
    `INSERT INTO zones (tenant_id, name, sort_order) VALUES (?, 'Lounge', 1)`,
    [tenantId]
  );
  const [zoneAussenResult] = await db.execute<any>(
    `INSERT INTO zones (tenant_id, name, sort_order) VALUES (?, 'Außen / Terrasse', 2)`,
    [tenantId]
  );

  const zoneInnenId  = zoneInnenResult.insertId  as number;
  const zoneLoungeId = zoneLoungeResult.insertId as number;
  const zoneAussenId = zoneAussenResult.insertId as number;

  // ─── Tische ──────────────────────────────────────────────────────────────
  // Innen: T1–T6
  for (let i = 1; i <= 6; i++) {
    await db.execute(
      `INSERT INTO tables (tenant_id, zone_id, name, is_active) VALUES (?, ?, ?, TRUE)`,
      [tenantId, zoneInnenId, `T${i}`]
    );
  }
  // Lounge: L1–L4
  for (let i = 1; i <= 4; i++) {
    await db.execute(
      `INSERT INTO tables (tenant_id, zone_id, name, is_active) VALUES (?, ?, ?, TRUE)`,
      [tenantId, zoneLoungeId, `L${i}`]
    );
  }
  // Außen: A1–A3
  for (let i = 1; i <= 3; i++) {
    await db.execute(
      `INSERT INTO tables (tenant_id, zone_id, name, is_active) VALUES (?, ?, ?, TRUE)`,
      [tenantId, zoneAussenId, `A${i}`]
    );
  }

  // ─── Bon-Sequenz ─────────────────────────────────────────────────────────
  // KassenSichV: fortlaufend, niemals zurücksetzen — Startwert 0
  await db.execute(
    `INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)`,
    [tenantId]
  );
}

export async function down(db: Connection): Promise<void> {
  // Seed-Daten entfernen — erlaubt, da keine Finanzdaten (GoBD greift erst bei
  // orders, order_items, receipts, payments, cancellations, audit_log, z_reports).
  // Reihenfolge: abhängige Datensätze zuerst.

  const [[tenantRow]] = await db.execute<any[]>(
    `SELECT id FROM tenants WHERE name = 'Shisha Lounge Berlin' AND address LIKE '%Kurfürstendamm 42%' LIMIT 1`
  );
  if (!tenantRow) return; // bereits entfernt
  const tenantId: number = tenantRow.id;

  await db.execute(`DELETE FROM receipt_sequences       WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM tables                  WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM zones                   WHERE tenant_id = ?`, [tenantId]);

  // Modifier-Optionen → Gruppen
  const [groups] = await db.execute<any[]>(
    `SELECT id FROM product_modifier_groups WHERE tenant_id = ?`, [tenantId]
  );
  for (const g of groups) {
    await db.execute(`DELETE FROM product_modifier_options WHERE modifier_group_id = ?`, [g.id]);
  }
  await db.execute(`DELETE FROM product_modifier_groups WHERE tenant_id = ?`, [tenantId]);

  await db.execute(`DELETE FROM products              WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM product_categories    WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM devices               WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM users                 WHERE tenant_id = ?`, [tenantId]);
  await db.execute(`DELETE FROM tenants               WHERE id        = ?`, [tenantId]);
}

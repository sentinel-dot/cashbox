// presets.test.ts — TC-I / REQ-PRESET: Starter-Sortimente (S17B).
// Idempotenz auf DB-Ebene (UNIQUE-Origin + preset_imports), GoBD-Service
// (kein aktives Produkt ohne verifizierte Historie), Pfand-Gate serverseitig.

import { describe, it, expect, beforeEach, vi } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import * as priceHistory from '../../services/priceHistory.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

vi.mock('../../services/priceHistory.js', { spy: true });

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function setup(conn: any, role: 'owner' | 'manager' | 'staff' = 'owner', plan = 'business') {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Preset GmbH', 'Str. 1, Berlin', ?, 'active')`,
    [plan]
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role) VALUES (?, 'O', 'o@t.de', ?, ?)`,
    [tenantId, hash, role]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}

// Kleines, gültiges Café-Subset: 1× standard, 1× food, 1× recipe_review
function cafeBody(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    preset_id: 'cafe',
    preset_version: 1,
    tax_basis_version: 'de-ust-2026-01',
    vat_confirmed: true,
    items: [
      { item_key: 'espresso',   name: 'Espresso',   price_cents: 280,
        vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'espresso' },
      { item_key: 'croissant',  name: 'Croissant',  price_cents: 320,
        vat_rate_inhouse: '7',  vat_rate_takeaway: '7',  visual_key: 'croissant' },
      { item_key: 'cappuccino', name: 'Cappuccino', price_cents: 390,
        vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'milk_coffee',
        review_confirmed: true },
    ],
    ...overrides,
  };
}

function doImport(token: string, body: unknown, key: string = crypto.randomUUID()) {
  return request(app)
    .post('/products/presets/import')
    .set('Authorization', `Bearer ${token}`)
    .set('Idempotency-Key', key)
    .send(body as object);
}

// ─── GET /products/presets ────────────────────────────────────────────────────

describe('GET /products/presets', () => {
  it('liefert alle vier Presets mit exakten Counts — auch für staff', async () => {
    const { token } = await setup(db, 'staff');
    const res = await request(app).get('/products/presets').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBe(4);

    const cafe = res.body.find((p: any) => p.preset_id === 'cafe');
    expect(cafe.version).toBe(1);
    expect(cafe.tax_basis_version).toBe('de-ust-2026-01');
    expect(cafe.categories.length).toBe(4);
    expect(cafe.products.length).toBe(25);
    // Farbrolle ist zu HEX aufgelöst
    expect(cafe.categories[0].color).toMatch(/^#[0-9a-f]{6}$/);

    const spaeti = res.body.find((p: any) => p.preset_id === 'spaeti');
    expect(spaeti.products.filter((p: any) => p.deposit_cents === 25).length).toBe(11);
    expect(spaeti.products.filter((p: any) => p.requires_custom_name).length).toBe(3);
  });
});

// ─── POST /products/presets/import ───────────────────────────────────────────

describe('POST /products/presets/import', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => {
    vi.mocked(priceHistory.writePriceHistory).mockRestore?.();
    ({ token, tenantId } = await setup(db));
  });

  it('Happy Path: Kategorien + Produkte mit initialer Historie, aktiv, korrekte Herkunft', async () => {
    const res = await doImport(token, cafeBody());
    expect(res.status).toBe(201);
    expect(res.body.imported.products).toBe(3);
    expect(res.body.imported.categories).toBe(2);   // coffee + bakery
    expect(res.body.skipped).toEqual([]);

    const [products] = await db.execute<any[]>(
      `SELECT id, name, price_cents, is_active, sort_order, visual_key,
              origin_preset_id, origin_item_key, category_id
       FROM products WHERE tenant_id = ? ORDER BY name`,
      [tenantId]
    );
    expect(products.length).toBe(3);
    for (const p of products) {
      expect(Boolean(p.is_active)).toBe(true);
      expect(p.origin_preset_id).toBe('cafe');
      expect(p.category_id).not.toBeNull();
      const [hist] = await db.execute<any[]>(
        'SELECT price_cents FROM product_price_history WHERE product_id = ? AND tenant_id = ?',
        [p.id, tenantId]
      );
      expect(hist.length).toBe(1);
      expect(hist[0].price_cents).toBe(p.price_cents);
    }

    const espresso = products.find(p => p.name === 'Espresso');
    expect(espresso.sort_order).toBe(10);            // aus der Preset-Definition
    expect(espresso.visual_key).toBe('espresso');

    const [cats] = await db.execute<any[]>(
      `SELECT name, color, origin_category_key FROM product_categories WHERE tenant_id = ?`,
      [tenantId]
    );
    expect(cats.length).toBe(2);
    expect(cats.map(c => c.origin_category_key).sort()).toEqual(['bakery', 'coffee']);
  });

  it('Replay mit demselben Idempotency-Key → 200 mit gespeichertem Ergebnis, keine neuen Zeilen', async () => {
    const key = crypto.randomUUID();
    const first = await doImport(token, cafeBody(), key);
    expect(first.status).toBe(201);

    const replay = await doImport(token, cafeBody(), key);
    expect(replay.status).toBe(200);
    expect(replay.body).toEqual(first.body);

    const [count] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(count[0].cnt).toBe(3);
  });

  it('Neuer Key, gleiches Preset → alles already_imported, keine Duplikate', async () => {
    await doImport(token, cafeBody());
    const second = await doImport(token, cafeBody());
    expect(second.status).toBe(201);
    expect(second.body.imported.products).toBe(0);
    expect(second.body.skipped.length).toBe(3);
    expect(second.body.skipped.every((s: any) => s.reason === 'already_imported')).toBe(true);

    const [count] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(count[0].cnt).toBe(3);

    const [histCount] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM product_price_history WHERE tenant_id = ?', [tenantId]
    );
    expect(histCount[0].cnt).toBe(3);   // keine zweite Historie je Produkt
  });

  it('Paralleler Doppeltap (gleicher Key) → genau ein Import, keine Duplikate', async () => {
    const key = crypto.randomUUID();
    const [a, b] = await Promise.all([
      doImport(token, cafeBody(), key),
      doImport(token, cafeBody(), key),
    ]);
    const statuses = [a.status, b.status].sort();
    // Ein Request verarbeitet (201); der andere sieht 'processing' (409) oder
    // — falls er später ankam — das Replay (200)
    expect([201]).toContain(statuses[1] === 201 ? 201 : statuses[0]);
    expect(statuses.filter(s => s === 201).length).toBe(1);

    const [count] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(count[0].cnt).toBe(3);
  });

  it('Failure-Injection: History-Fehler → 500, Produkt bleibt inaktiv; Retry repariert', async () => {
    const key = crypto.randomUUID();
    const body = cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 280,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'espresso' }],
    });

    vi.mocked(priceHistory.writePriceHistory).mockImplementationOnce(async () => {
      throw new Error('auditDb down');
    });

    const failed = await doImport(token, body, key);
    expect(failed.status).toBe(500);

    // Produkt existiert, ist aber INAKTIV und hat keine Historie — nie verkaufsfähig
    const [afterFail] = await db.execute<any[]>(
      'SELECT id, is_active FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(afterFail.length).toBe(1);
    expect(Boolean(afterFail[0].is_active)).toBe(false);
    const [histAfterFail] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM product_price_history WHERE product_id = ?', [afterFail[0].id]
    );
    expect(histAfterFail[0].cnt).toBe(0);

    // Retry mit demselben Key: repariert denselben Datensatz (kein Duplikat)
    const retry = await doImport(token, body, key);
    expect(retry.status).toBe(201);
    expect(retry.body.imported.products).toBe(1);

    const [afterRetry] = await db.execute<any[]>(
      'SELECT id, is_active FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(afterRetry.length).toBe(1);
    expect(afterRetry[0].id).toBe(afterFail[0].id);
    expect(Boolean(afterRetry[0].is_active)).toBe(true);
    const [histAfterRetry] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM product_price_history WHERE product_id = ?', [afterRetry[0].id]
    );
    expect(histAfterRetry[0].cnt).toBe(1);
  });

  it('Vom Betreiber deaktiviertes Import-Produkt wird durch Re-Import NICHT reaktiviert', async () => {
    await doImport(token, cafeBody());
    // Betreiber deaktiviert den Espresso
    await db.execute(
      `UPDATE products SET is_active = FALSE WHERE tenant_id = ? AND origin_item_key = 'espresso'`,
      [tenantId]
    );

    const reimport = await doImport(token, cafeBody());
    expect(reimport.status).toBe(201);

    const [rows] = await db.execute<any[]>(
      `SELECT is_active FROM products WHERE tenant_id = ? AND origin_item_key = 'espresso'`,
      [tenantId]
    );
    expect(rows.length).toBe(1);
    expect(Boolean(rows[0].is_active)).toBe(false);   // bleibt deaktiviert
    expect(reimport.body.skipped.some((s: any) => s.item_key === 'espresso' && s.reason === 'already_imported')).toBe(true);
  });

  it('Namenskollision mit manuell angelegtem Produkt → skip (Default), create legt trotzdem an', async () => {
    await db.execute(
      `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
       VALUES (?, 'Espresso', 250, '19', '19')`,
      [tenantId]
    );

    const body = cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 280,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'espresso' }],
    });
    const skipRes = await doImport(token, body);
    expect(skipRes.status).toBe(201);
    expect(skipRes.body.imported.products).toBe(0);
    expect(skipRes.body.skipped[0]).toEqual({ item_key: 'espresso', reason: 'name_collision' });

    const createBody = cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 280,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'espresso',
                on_name_collision: 'create' }],
    });
    const createRes = await doImport(token, createBody);
    expect(createRes.status).toBe(201);
    expect(createRes.body.imported.products).toBe(1);
  });

  it('Tenant-Isolation: zweiter Tenant importiert unabhängig, keine Sichtbarkeit über Grenzen', async () => {
    await doImport(token, cafeBody());
    const { token: tokenB, tenantId: tenantB } = await setup(db);
    const resB = await doImport(tokenB, cafeBody());
    expect(resB.status).toBe(201);
    expect(resB.body.imported.products).toBe(3);   // unabhängig, kein already_imported

    const [aProducts] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantId]
    );
    const [bProducts] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantB]
    );
    expect(aProducts[0].cnt).toBe(3);
    expect(bProducts[0].cnt).toBe(3);

    const listA = await request(app).get('/products').set('Authorization', `Bearer ${token}`);
    expect(listA.body.length).toBe(3);
  });

  it('staff darf nicht importieren → 403', async () => {
    const { token: staffToken } = await setup(db, 'staff');
    const res = await doImport(staffToken, cafeBody());
    expect(res.status).toBe(403);
  });

  it('Pfand-Gate: Späti-Pfandzeile wird serverseitig abgewiesen (400, code deposit_gate)', async () => {
    const res = await doImport(token, {
      preset_id: 'spaeti', preset_version: 1,
      tax_basis_version: 'de-ust-2026-01', vat_confirmed: true,
      items: [{ item_key: 'pils_can_050', name: 'Pils, Dose 0,5 l', price_cents: 180,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'beer' }],
    });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('deposit_gate');
    expect(res.body.item_keys).toEqual(['pils_can_050']);

    const [count] = await db.execute<any[]>(
      'SELECT COUNT(*) AS cnt FROM products WHERE tenant_id = ?', [tenantId]
    );
    expect(count[0].cnt).toBe(0);
  });

  it('Tabakvorlage ohne konkreten Namen → 400 custom_name_required', async () => {
    const res = await doImport(token, {
      preset_id: 'spaeti', preset_version: 1,
      tax_basis_version: 'de-ust-2026-01', vat_confirmed: true,
      items: [{ item_key: 'cigarettes_custom', name: 'Zigaretten (Vorlage)', price_cents: 850,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'cigarettes',
                review_confirmed: true }],
    });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('custom_name_required');
  });

  it('review-Zeile ohne Einzelbestätigung → 400 review_required', async () => {
    const body = cafeBody();
    delete (body.items[2] as any).review_confirmed;
    const res = await doImport(token, body);
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('review_required');
  });

  it('Abweichender Satz auf Standard-Zeile → 400', async () => {
    const body = cafeBody();
    (body.items[0] as any).vat_rate_inhouse = '7';
    const res = await doImport(token, body);
    expect(res.status).toBe(400);
  });

  it('400/422-Matrix: unbekannter item_key, Float-Preis, 0-Preis, fehlende Bestätigung, fehlender Key, ungültiger visual_key', async () => {
    // Unbekannter item_key → 400
    const unknown = await doImport(token, cafeBody({
      items: [{ item_key: 'gibt_es_nicht', name: 'X', price_cents: 100,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: null }],
    }));
    expect(unknown.status).toBe(400);

    // Float-Preis → 422 (Zod)
    const float = await doImport(token, cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 2.8,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: null }],
    }));
    expect(float.status).toBe(422);

    // 0-Preis → 422 (positive())
    const zero = await doImport(token, cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 0,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: null }],
    }));
    expect(zero.status).toBe(422);

    // vat_confirmed fehlt → 422 (literal true)
    const unconfirmed = await doImport(token, cafeBody({ vat_confirmed: false }));
    expect(unconfirmed.status).toBe(422);

    // Idempotency-Key fehlt → 400
    const noKey = await request(app)
      .post('/products/presets/import')
      .set('Authorization', `Bearer ${token}`)
      .send(cafeBody());
    expect(noKey.status).toBe(400);

    // Ungültiger visual_key → 422 (Whitelist)
    const badVisual = await doImport(token, cafeBody({
      items: [{ item_key: 'espresso', name: 'Espresso', price_cents: 280,
                vat_rate_inhouse: '19', vat_rate_takeaway: '19', visual_key: 'sf.symbol.name' }],
    }));
    expect(badVisual.status).toBe(422);
  });

  it('Plan-Limit: starter-Tenant kann nicht über 50 Produkte importieren', async () => {
    const { token: starterToken, tenantId: starterTenant } = await setup(db, 'owner', 'starter');
    // 49 Produkte anlegen → 49 + 3 > 50
    for (let i = 0; i < 49; i++) {
      await db.execute(
        `INSERT INTO products (tenant_id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway)
         VALUES (?, ?, 100, '19', '19')`,
        [starterTenant, `Produkt ${i}`]
      );
    }
    const res = await doImport(starterToken, cafeBody());
    expect(res.status).toBe(403);
    expect(res.body.error).toContain('Plan-Limit');
  });
});

// ─── Gehärteter POST /products (S17B: gemeinsamer GoBD-Service) ──────────────

describe('POST /products — gehärtet über createProductWithHistory', () => {
  let token: string; let tenantId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));
  });

  it('History-Fehler → 500, kein aktives Produkt ohne Historie', async () => {
    vi.mocked(priceHistory.writePriceHistory).mockImplementationOnce(async () => {
      throw new Error('auditDb down');
    });

    const res = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Kaputt', price_cents: 1000, vat_rate_inhouse: '19' });
    expect(res.status).toBe(500);

    const [rows] = await db.execute<any[]>(
      `SELECT is_active FROM products WHERE tenant_id = ? AND name = 'Kaputt'`,
      [tenantId]
    );
    // Rest existiert, aber inaktiv — nie verkaufsfähig ohne Historie
    expect(rows.length).toBe(1);
    expect(Boolean(rows[0].is_active)).toBe(false);
  });

  it('visual_key wird angenommen, persistiert und per PATCH änderbar', async () => {
    const created = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Tee', price_cents: 300, vat_rate_inhouse: '19', visual_key: 'tea' });
    expect(created.status).toBe(201);
    expect(created.body.visual_key).toBe('tea');

    const patched = await request(app)
      .patch(`/products/${created.body.id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ visual_key: 'coffee' });
    expect(patched.status).toBe(200);

    const [rows] = await db.execute<any[]>(
      'SELECT visual_key FROM products WHERE id = ?', [created.body.id]
    );
    expect(rows[0].visual_key).toBe('coffee');

    // Whitelist: SF-Symbol-Namen o.ä. werden abgewiesen
    const bad = await request(app)
      .post('/products')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X', price_cents: 100, vat_rate_inhouse: '19', visual_key: 'cup.and.saucer.fill' });
    expect(bad.status).toBe(422);
  });
});

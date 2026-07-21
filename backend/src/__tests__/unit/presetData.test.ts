// presetData.test.ts — TC-U / REQ-PRESET: Build-Time-Garantien für die V1-Presets
// (docs/s17-sortiment-starterpakete.md §11 „Backend Unit").

import { describe, it, expect } from 'vitest';
import { ALL_PRESETS, getPreset } from '../../services/presets/presetData.js';
import { VISUAL_KEYS, TAX_BASIS_VERSION } from '../../services/presets/presetTypes.js';

const byId = Object.fromEntries(ALL_PRESETS.map(p => [p.preset_id, p]));

describe('VISUAL_KEYS-Katalog', () => {
  it('enthält exakt 39 eindeutige Schlüssel inkl. generic', () => {
    expect(VISUAL_KEYS.length).toBe(39);
    expect(new Set(VISUAL_KEYS).size).toBe(39);
    expect(VISUAL_KEYS).toContain('generic');
  });

  it('Schlüssel sind ASCII-kleingeschrieben (maschinenstabil)', () => {
    for (const key of VISUAL_KEYS) {
      expect(key).toMatch(/^[a-z][a-z0-9_]*$/);
    }
  });
});

describe('Preset-Struktur', () => {
  it('genau vier Presets mit eindeutigen IDs, Version 1, richtiger Steuerbasis', () => {
    expect(ALL_PRESETS.length).toBe(4);
    expect(new Set(ALL_PRESETS.map(p => p.preset_id)).size).toBe(4);
    for (const preset of ALL_PRESETS) {
      expect(preset.version).toBe(1);
      expect(preset.tax_basis_version).toBe(TAX_BASIS_VERSION);
    }
  });

  it('exakte Counts: Shisha-Bar 4/21, Café 4/25, Späti 5/27+3 Vorlagen, Leer 0/0', () => {
    expect(byId['shisha_bar'].categories.length).toBe(4);
    expect(byId['shisha_bar'].products.length).toBe(21);
    expect(byId['cafe'].categories.length).toBe(4);
    expect(byId['cafe'].products.length).toBe(25);
    expect(byId['spaeti'].categories.length).toBe(5);
    const spaetiTemplates = byId['spaeti'].products.filter(p => p.requires_custom_name);
    expect(spaetiTemplates.length).toBe(3);
    expect(byId['spaeti'].products.length - spaetiTemplates.length).toBe(27);
    expect(byId['empty'].categories.length).toBe(0);
    expect(byId['empty'].products.length).toBe(0);
  });

  it('item_keys und category_keys sind je Preset eindeutig', () => {
    for (const preset of ALL_PRESETS) {
      const itemKeys = preset.products.map(p => p.item_key);
      const catKeys  = preset.categories.map(c => c.category_key);
      expect(new Set(itemKeys).size).toBe(itemKeys.length);
      expect(new Set(catKeys).size).toBe(catKeys.length);
    }
  });

  it('jede Produktzeile referenziert eine vorhandene Kategorie und einen bekannten visual_key', () => {
    for (const preset of ALL_PRESETS) {
      const catKeys = new Set(preset.categories.map(c => c.category_key));
      for (const product of preset.products) {
        expect(catKeys.has(product.category_key), `${preset.preset_id}/${product.item_key}`).toBe(true);
        if (product.visual_key !== null) {
          expect(VISUAL_KEYS).toContain(product.visual_key);
        }
      }
    }
  });

  it('sort_order ist je Kategorie eindeutig und deterministisch', () => {
    for (const preset of ALL_PRESETS) {
      const perCategory = new Map<string, number[]>();
      for (const product of preset.products) {
        const list = perCategory.get(product.category_key) ?? [];
        list.push(product.sort_order);
        perCategory.set(product.category_key, list);
      }
      for (const [catKey, sorts] of perCategory) {
        expect(new Set(sorts).size, `${preset.preset_id}/${catKey}`).toBe(sorts.length);
      }
      const catSorts = preset.categories.map(c => c.sort_order);
      expect(new Set(catSorts).size).toBe(catSorts.length);
    }
  });
});

describe('MwSt.-Leitplanken (§2)', () => {
  it('nur 7 oder 19; kein Preis im Preset (price_cents null)', () => {
    for (const preset of ALL_PRESETS) {
      for (const product of preset.products) {
        expect(['7', '19']).toContain(product.vat_rate_inhouse);
        expect(['7', '19']).toContain(product.vat_rate_takeaway);
        expect(product.price_cents).toBeNull();
      }
    }
  });

  it('recipe_review exakt auf der definierten Allowlist (Milchgetränke)', () => {
    const allowlist = new Set([
      'shisha_bar/latte_macchiato',
      'cafe/cappuccino', 'cafe/latte_macchiato', 'cafe/milk_coffee', 'cafe/hot_chocolate',
    ]);
    const actual = new Set<string>();
    for (const preset of ALL_PRESETS) {
      for (const product of preset.products) {
        if (product.vat_review === 'recipe_review') {
          actual.add(`${preset.preset_id}/${product.item_key}`);
        }
      }
    }
    expect(actual).toEqual(allowlist);
  });

  it('printed_price_review nur auf den drei Tabakvorlagen (Späti)', () => {
    for (const preset of ALL_PRESETS) {
      for (const product of preset.products) {
        if (product.vat_review === 'printed_price_review') {
          expect(preset.preset_id).toBe('spaeti');
          expect(product.requires_custom_name).toBe(true);
          expect(product.requires_exact_price).toBe(true);
        }
        if (product.requires_custom_name) {
          expect(product.vat_review).toBe('printed_price_review');
        }
      }
    }
  });

  it('food_7_2026 nur mit 7/7, standard_19 nur mit 19/19 (V1-Daten)', () => {
    for (const preset of ALL_PRESETS) {
      for (const product of preset.products) {
        if (product.vat_review === 'food_7_2026') {
          expect(product.vat_rate_inhouse).toBe('7');
          expect(product.vat_rate_takeaway).toBe('7');
        }
        if (product.vat_review === 'standard_19') {
          expect(product.vat_rate_inhouse).toBe('19');
          expect(product.vat_rate_takeaway).toBe('19');
        }
      }
    }
  });
});

describe('Pfand-Gate (§5.4)', () => {
  it('deposit_cents ausschließlich 0 oder 25; genau elf Späti-Produkte tragen 25', () => {
    let depositCount = 0;
    for (const preset of ALL_PRESETS) {
      for (const product of preset.products) {
        expect([0, 25]).toContain(product.deposit_cents);
        if (product.deposit_cents === 25) {
          expect(preset.preset_id).toBe('spaeti');
          depositCount++;
        }
      }
    }
    expect(depositCount).toBe(11);
  });
});

describe('getPreset', () => {
  it('liefert Preset nur bei exakter Version', () => {
    expect(getPreset('cafe', 1)?.display_name).toBe('Café');
    expect(getPreset('cafe', 2)).toBeNull();
  });
});

// presetData.ts — S17B: die vier V1-Presets, wörtlich aus
// docs/s17-sortiment-starterpakete.md §3–5 übernommen (Preset-Datenstand: Version 1).
// Jede fachliche Änderung (Produktmenge, MwSt.-Vorschlag, Kategorie, Importverhalten)
// erhöht die Preset-Version — Textkorrekturen ohne Datenänderung nicht.

import {
  AssortmentPreset, AssortmentPresetProduct, PresetId, TAX_BASIS_VERSION,
} from './presetTypes.js';

// Kurzform-Helfer: Standardzeile ohne Pfand/Vorlagen-Flags
function p(
  item_key: string, category_key: string, name_de: string, sort_order: number,
  vat: AssortmentPresetProduct['vat_rate_inhouse'],
  vat_review: AssortmentPresetProduct['vat_review'],
  visual_key: AssortmentPresetProduct['visual_key'],
  deposit_cents: 0 | 25 = 0,
): AssortmentPresetProduct {
  return {
    item_key, category_key, name_de, sort_order,
    price_cents: null,
    vat_rate_inhouse: vat, vat_rate_takeaway: vat,
    vat_review, visual_key, deposit_cents,
  };
}

// ─── Preset shisha_bar@1 (§3) — 4 Kategorien, 21 Produkte ────────────────────

const SHISHA_BAR: AssortmentPreset = {
  preset_id: 'shisha_bar',
  display_name: 'Shisha-Bar',
  version: 1,
  tax_basis_version: TAX_BASIS_VERSION,
  categories: [
    { category_key: 'shisha',      name_de: 'Shisha',         sort_order: 10, color_role: 'plum' },
    { category_key: 'cold_drinks', name_de: 'Kalte Getränke', sort_order: 20, color_role: 'blue' },
    { category_key: 'hot_drinks',  name_de: 'Heißgetränke',   sort_order: 30, color_role: 'amber' },
    { category_key: 'snacks',      name_de: 'Snacks',         sort_order: 40, color_role: 'green' },
  ],
  products: [
    p('shisha_classic',        'shisha',      'Shisha Klassik',     10, '19', 'standard_19',   'shisha'),
    p('shisha_premium',        'shisha',      'Shisha Premium',     20, '19', 'standard_19',   'shisha'),
    p('shisha_fruit_bowl',     'shisha',      'Shisha Fruchtkopf',  30, '19', 'standard_19',   'shisha'),
    p('shisha_head_change',    'shisha',      'Kopfwechsel',        40, '19', 'standard_19',   'shisha_refill'),
    p('shisha_extra_charcoal', 'shisha',      'Kohle extra',        50, '19', 'standard_19',   'charcoal'),
    p('water_still',           'cold_drinks', 'Wasser still',       10, '19', 'standard_19',   'water'),
    p('water_sparkling',       'cold_drinks', 'Wasser sprudel',     20, '19', 'standard_19',   'water'),
    p('cola',                  'cold_drinks', 'Cola',               30, '19', 'standard_19',   'soft_drink'),
    p('cola_zero',             'cold_drinks', 'Cola ohne Zucker',   40, '19', 'standard_19',   'soft_drink'),
    p('orange_soda',           'cold_drinks', 'Orangenlimonade',    50, '19', 'standard_19',   'soft_drink'),
    p('apple_spritzer',        'cold_drinks', 'Apfelschorle',       60, '19', 'standard_19',   'spritzer'),
    p('energy_drink',          'cold_drinks', 'Energydrink',        70, '19', 'standard_19',   'energy_drink'),
    p('black_tea',             'hot_drinks',  'Schwarzer Tee',      10, '19', 'standard_19',   'tea'),
    p('fresh_mint_tea',        'hot_drinks',  'Frischer Minztee',   20, '19', 'standard_19',   'tea'),
    p('espresso',              'hot_drinks',  'Espresso',           30, '19', 'standard_19',   'espresso'),
    p('cafe_creme',            'hot_drinks',  'Café Crème',         40, '19', 'standard_19',   'coffee'),
    p('latte_macchiato',       'hot_drinks',  'Latte Macchiato',    50, '19', 'recipe_review', 'milk_coffee'),
    p('nachos_dip',            'snacks',      'Nachos mit Dip',     10, '7',  'food_7_2026',   'nachos'),
    p('potato_chips',          'snacks',      'Kartoffelchips',     20, '7',  'food_7_2026',   'chips'),
    p('salted_nuts',           'snacks',      'Salzige Nüsse',      30, '7',  'food_7_2026',   'nuts'),
    p('fruit_plate',           'snacks',      'Obstteller',         40, '7',  'food_7_2026',   'fruit'),
  ],
};

// ─── Preset cafe@1 (§4) — 4 Kategorien, 25 Produkte ──────────────────────────

const CAFE: AssortmentPreset = {
  preset_id: 'cafe',
  display_name: 'Café',
  version: 1,
  tax_basis_version: TAX_BASIS_VERSION,
  categories: [
    { category_key: 'coffee',          name_de: 'Kaffee',              sort_order: 10, color_role: 'brown' },
    { category_key: 'tea_cold_drinks', name_de: 'Tee & Kaltgetränke',  sort_order: 20, color_role: 'blue' },
    { category_key: 'bakery',          name_de: 'Backwaren',           sort_order: 30, color_role: 'orange' },
    { category_key: 'meals',           name_de: 'Frühstück & Speisen', sort_order: 40, color_role: 'green' },
  ],
  products: [
    p('espresso',            'coffee',          'Espresso',                   10, '19', 'standard_19',   'espresso'),
    p('espresso_double',     'coffee',          'Espresso doppio',            20, '19', 'standard_19',   'espresso'),
    p('cafe_creme',          'coffee',          'Café Crème',                 30, '19', 'standard_19',   'coffee'),
    p('americano',           'coffee',          'Americano',                  40, '19', 'standard_19',   'coffee'),
    p('cappuccino',          'coffee',          'Cappuccino',                 50, '19', 'recipe_review', 'milk_coffee'),
    p('latte_macchiato',     'coffee',          'Latte Macchiato',            60, '19', 'recipe_review', 'milk_coffee'),
    p('milk_coffee',         'coffee',          'Milchkaffee',                70, '19', 'recipe_review', 'milk_coffee'),
    p('hot_chocolate',       'coffee',          'Heiße Schokolade',           80, '19', 'recipe_review', 'hot_chocolate'),
    p('tea',                 'tea_cold_drinks', 'Tee',                        10, '19', 'standard_19',   'tea'),
    p('fresh_mint_tea',      'tea_cold_drinks', 'Frischer Minztee',           20, '19', 'standard_19',   'tea'),
    p('water_still',         'tea_cold_drinks', 'Wasser still',               30, '19', 'standard_19',   'water'),
    p('water_sparkling',     'tea_cold_drinks', 'Wasser sprudel',             40, '19', 'standard_19',   'water'),
    p('cola',                'tea_cold_drinks', 'Cola',                       50, '19', 'standard_19',   'soft_drink'),
    p('apple_spritzer',      'tea_cold_drinks', 'Apfelschorle',               60, '19', 'standard_19',   'spritzer'),
    p('orange_juice',        'tea_cold_drinks', 'Orangensaft',                70, '19', 'standard_19',   'juice'),
    p('croissant',           'bakery',          'Croissant',                  10, '7',  'food_7_2026',   'croissant'),
    p('chocolate_croissant', 'bakery',          'Schokocroissant',            20, '7',  'food_7_2026',   'croissant'),
    p('butter_pretzel',      'bakery',          'Butterbrezel',               30, '7',  'food_7_2026',   'pretzel'),
    p('cheese_roll',         'bakery',          'Belegtes Brötchen Käse',     40, '7',  'food_7_2026',   'sandwich'),
    p('ham_roll',            'bakery',          'Belegtes Brötchen Schinken', 50, '7',  'food_7_2026',   'sandwich'),
    p('cake_slice',          'bakery',          'Kuchen, Stück',              60, '7',  'food_7_2026',   'cake'),
    p('breakfast_small',     'meals',           'Frühstück klein',            10, '7',  'food_7_2026',   'breakfast'),
    p('breakfast_large',     'meals',           'Frühstück groß',             20, '7',  'food_7_2026',   'breakfast'),
    p('scrambled_eggs',      'meals',           'Rührei',                     30, '7',  'food_7_2026',   'egg_dish'),
    p('daily_soup',          'meals',           'Tagessuppe',                 40, '7',  'food_7_2026',   'soup'),
  ],
};

// ─── Preset spaeti@1 (§5) — 5 Kategorien, 27 Produkte + 3 Tabakvorlagen ──────

const SPAETI: AssortmentPreset = {
  preset_id: 'spaeti',
  display_name: 'Späti',
  version: 1,
  tax_basis_version: TAX_BASIS_VERSION,
  categories: [
    { category_key: 'cold_drinks',  name_de: 'Alkoholfreie Getränke', sort_order: 10, color_role: 'blue' },
    { category_key: 'beer_wine',    name_de: 'Bier & Wein',           sort_order: 20, color_role: 'indigo' },
    { category_key: 'snacks_sweets', name_de: 'Snacks & Süßes',       sort_order: 30, color_role: 'orange' },
    { category_key: 'everyday',     name_de: 'Alltag',                sort_order: 40, color_role: 'gray' },
    { category_key: 'tobacco',      name_de: 'Tabak',                 sort_order: 50, color_role: 'brown' },
  ],
  products: [
    // Alkoholfreie Getränke — Pfandzeilen (25) unterliegen dem Release-Gate §5.4
    p('water_still_pet_050',      'cold_drinks',  'Wasser still, PET 0,5 l',       10, '19', 'standard_19', 'water',        25),
    p('water_sparkling_pet_050',  'cold_drinks',  'Wasser sprudel, PET 0,5 l',     20, '19', 'standard_19', 'water',        25),
    p('cola_can_033',             'cold_drinks',  'Cola, Dose 0,33 l',             30, '19', 'standard_19', 'soft_drink',   25),
    p('cola_zero_can_033',        'cold_drinks',  'Cola ohne Zucker, Dose 0,33 l', 40, '19', 'standard_19', 'soft_drink',   25),
    p('orange_soda_can_033',      'cold_drinks',  'Orangenlimonade, Dose 0,33 l',  50, '19', 'standard_19', 'soft_drink',   25),
    p('apple_spritzer_pet_050',   'cold_drinks',  'Apfelschorle, PET 0,5 l',       60, '19', 'standard_19', 'spritzer',     25),
    p('energy_can_025',           'cold_drinks',  'Energydrink, Dose 0,25 l',      70, '19', 'standard_19', 'energy_drink', 25),
    p('orange_juice_carton_100',  'cold_drinks',  'Orangensaft, Karton 1,0 l',     80, '19', 'standard_19', 'juice'),
    // Bier & Wein
    p('pils_can_050',             'beer_wine',    'Pils, Dose 0,5 l',              10, '19', 'standard_19', 'beer',         25),
    p('lager_can_050',            'beer_wine',    'Lager, Dose 0,5 l',             20, '19', 'standard_19', 'beer',         25),
    p('radler_can_050',           'beer_wine',    'Radler, Dose 0,5 l',            30, '19', 'standard_19', 'beer',         25),
    p('alcohol_free_beer_can_050','beer_wine',    'Bier alkoholfrei, Dose 0,5 l',  40, '19', 'standard_19', 'beer',         25),
    p('red_wine_bottle_075',      'beer_wine',    'Rotwein, Flasche 0,75 l',       50, '19', 'standard_19', 'wine'),
    p('white_wine_bottle_075',    'beer_wine',    'Weißwein, Flasche 0,75 l',      60, '19', 'standard_19', 'wine'),
    // Snacks & Süßes
    p('potato_chips_150',         'snacks_sweets', 'Kartoffelchips, 150 g',        10, '7',  'food_7_2026', 'chips'),
    p('salted_peanuts_200',       'snacks_sweets', 'Salzige Erdnüsse, 200 g',      20, '7',  'food_7_2026', 'nuts'),
    p('chocolate_bar',            'snacks_sweets', 'Schokoriegel',                 30, '7',  'food_7_2026', 'chocolate'),
    p('gummy_candy_200',          'snacks_sweets', 'Fruchtgummi, 200 g',           40, '7',  'food_7_2026', 'gummy_candy'),
    p('cookies_200',              'snacks_sweets', 'Kekse, 200 g',                 50, '7',  'food_7_2026', 'cookies'),
    p('chewing_gum',              'snacks_sweets', 'Kaugummi',                     60, '7',  'food_7_2026', 'gummy_candy'),
    p('ice_pop',                  'snacks_sweets', 'Eis am Stiel',                 70, '7',  'food_7_2026', 'ice_cream'),
    p('instant_noodles_cup',      'snacks_sweets', 'Instantnudeln, Becher',        80, '7',  'food_7_2026', 'instant_meal'),
    // Alltag
    p('lighter',                  'everyday',     'Feuerzeug',                     10, '19', 'standard_19', 'lighter'),
    p('tissues',                  'everyday',     'Taschentücher',                 20, '19', 'standard_19', 'tissues'),
    p('battery_aa_4',             'everyday',     'Batterien AA, 4er',             30, '19', 'standard_19', 'battery'),
    p('battery_aaa_4',            'everyday',     'Batterien AAA, 4er',            40, '19', 'standard_19', 'battery'),
    p('usb_c_cable',              'everyday',     'Ladekabel USB-C',               50, '19', 'standard_19', 'cable'),
    // Tabakvorlagen (§5.3): standardmäßig abgewählt; Name = "[Marke] [Variante], [Menge]",
    // Preis = aufgedruckter Packungs-/Kleinverkaufspreis (TabStG §§ 26/28)
    {
      item_key: 'cigarettes_custom', category_key: 'tobacco',
      name_de: 'Zigaretten (Vorlage)', sort_order: 10,
      price_cents: null, vat_rate_inhouse: '19', vat_rate_takeaway: '19',
      vat_review: 'printed_price_review', visual_key: 'cigarettes', deposit_cents: 0,
      requires_custom_name: true, requires_exact_price: true,
    },
    {
      item_key: 'fine_cut_tobacco_custom', category_key: 'tobacco',
      name_de: 'Feinschnitttabak (Vorlage)', sort_order: 20,
      price_cents: null, vat_rate_inhouse: '19', vat_rate_takeaway: '19',
      vat_review: 'printed_price_review', visual_key: 'tobacco', deposit_cents: 0,
      requires_custom_name: true, requires_exact_price: true,
    },
    {
      item_key: 'hookah_tobacco_custom', category_key: 'tobacco',
      name_de: 'Wasserpfeifentabak (Vorlage)', sort_order: 30,
      price_cents: null, vat_rate_inhouse: '19', vat_rate_takeaway: '19',
      vat_review: 'printed_price_review', visual_key: 'tobacco', deposit_cents: 0,
      requires_custom_name: true, requires_exact_price: true,
    },
  ],
};

// ─── Preset empty@1 ──────────────────────────────────────────────────────────

const EMPTY: AssortmentPreset = {
  preset_id: 'empty',
  display_name: 'Leer starten',
  version: 1,
  tax_basis_version: TAX_BASIS_VERSION,
  categories: [],
  products: [],
};

// ─── Zugriff ─────────────────────────────────────────────────────────────────

export const ALL_PRESETS: readonly AssortmentPreset[] = [SHISHA_BAR, CAFE, SPAETI, EMPTY];

export function getPreset(presetId: PresetId, version: number): AssortmentPreset | null {
  const preset = ALL_PRESETS.find(pr => pr.preset_id === presetId);
  if (!preset || preset.version !== version) return null;
  return preset;
}

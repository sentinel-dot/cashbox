// presetTypes.ts — S17B: typisierte, versionierte Starter-Sortimente.
// Verbindliche Quelle: docs/s17-sortiment-starterpakete.md (§6 Visual-Katalog,
// §7 Struktur). Freie Strings im Importpfad sind nicht zulässig — alles läuft
// über diese Typen und die VISUAL_KEYS-Whitelist.

// §6.2 — endgültiger V1-Katalog (39 Schlüssel). Ein Schlüssel ändert nach
// Veröffentlichung nie seine Bedeutung; neue Motive bekommen neue Schlüssel.
export const VISUAL_KEYS = [
  'generic',
  'shisha', 'shisha_refill', 'charcoal', 'tobacco', 'smoking_accessory',
  'espresso', 'coffee', 'milk_coffee', 'tea', 'hot_chocolate',
  'water', 'soft_drink', 'spritzer', 'energy_drink', 'juice',
  'beer', 'wine',
  'breakfast', 'egg_dish', 'soup', 'sandwich',
  'croissant', 'pretzel', 'cake',
  'nachos', 'chips', 'nuts', 'fruit',
  'chocolate', 'gummy_candy', 'cookies', 'ice_cream', 'instant_meal',
  'cigarettes', 'lighter', 'tissues', 'battery', 'cable',
] as const;

export type VisualKey = typeof VISUAL_KEYS[number];

export type VatRate = '7' | '19';

// §2.3 Prüfklassen — recipe_review/printed_price_review verlangen Einzelbestätigung
export type VatReview =
  | 'standard_19'
  | 'food_7_2026'
  | 'recipe_review'
  | 'printed_price_review';

export type PresetId = 'shisha_bar' | 'cafe' | 'spaeti' | 'empty';

export const TAX_BASIS_VERSION = 'de-ust-2026-01' as const;

// Farbrollen (§3.1 usw.) → konkrete HEX-Werte in der Ledger-Signatur
// (gedämpfte, erdige Mitteltöne — passend zu den App-Farb-Presets)
export type ColorRole =
  | 'plum' | 'blue' | 'amber' | 'green'
  | 'brown' | 'orange' | 'indigo' | 'gray';

export const COLOR_ROLE_HEX: Record<ColorRole, string> = {
  plum:   '#6e5a9e',
  blue:   '#3a7ca5',
  amber:  '#9a6a0b',
  green:  '#4a7310',
  brown:  '#8a5a2b',
  orange: '#b4552d',
  indigo: '#46589e',
  gray:   '#6b7267',
};

export interface AssortmentPresetCategory {
  category_key: string;
  name_de:      string;
  sort_order:   number;
  color_role:   ColorRole;
}

export interface AssortmentPresetProduct {
  item_key:          string;
  category_key:      string;
  name_de:           string;
  sort_order:        number;
  price_cents:       null;          // §1.2: keine Produktionspreise im Preset
  vat_rate_inhouse:  VatRate;
  vat_rate_takeaway: VatRate;
  vat_review:        VatReview;
  visual_key:        VisualKey | null;
  deposit_cents:     0 | 25;        // §5.4: 25 ⇒ Release-Gate, Import gesperrt
  requires_custom_name?: boolean;   // §5.3 Tabakvorlagen
  requires_exact_price?: boolean;   // §5.3: aufgedruckter Packungspreis
}

export interface AssortmentPreset {
  preset_id:         PresetId;
  display_name:      string;
  version:           1;
  tax_basis_version: typeof TAX_BASIS_VERSION;
  categories:        readonly AssortmentPresetCategory[];
  products:          readonly AssortmentPresetProduct[];
}

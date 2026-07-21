// PresetModels.swift — S17B: Decodables für GET /products/presets und der
// Request/Response-Vertrag von POST /products/presets/import.
// visual_key bewusst String? (unbekannte Zukunftswerte ⇒ generic-Fallback,
// nie Decode-Fehler); deposit_cents > 0 ⇒ Zeile ist bis zum Pfand-Paket gesperrt.

import Foundation

// ── GET /products/presets ────────────────────────────────────────────────────

struct AssortmentPreset: Decodable, Identifiable {
    let presetId:        String
    let displayName:     String
    let version:         Int
    let taxBasisVersion: String
    let categories:      [PresetCategory]
    let products:        [PresetProduct]

    var id: String { presetId }

    /// Direkt importierbare Zeilen (ohne Vorlagen und Pfand-gesperrte)
    var readyProducts: [PresetProduct] {
        products.filter { !$0.isTemplate && !$0.isDepositBlocked }
    }
}

struct PresetCategory: Decodable, Identifiable {
    let categoryKey: String
    let nameDe:      String
    let sortOrder:   Int
    let color:       String   // Backend löst die Farbrolle zu HEX auf

    var id: String { categoryKey }
}

struct PresetProduct: Decodable, Identifiable {
    let itemKey:            String
    let categoryKey:        String
    let nameDe:             String
    let sortOrder:          Int
    let vatRateInhouse:     String
    let vatRateTakeaway:    String
    let vatReview:          String   // String statt Enum: zukünftige Klassen tolerieren
    let visualKey:          String?
    let depositCents:       Int
    let requiresCustomName: Bool?
    let requiresExactPrice: Bool?

    var id: String { itemKey }

    var isTemplate:       Bool { requiresCustomName == true }
    var isDepositBlocked: Bool { depositCents > 0 }
    /// §2.3: recipe_review + printed_price_review brauchen Einzelbestätigung
    var needsIndividualReview: Bool {
        vatReview == "recipe_review" || vatReview == "printed_price_review"
    }
}

// ── POST /products/presets/import ────────────────────────────────────────────

struct PresetImportItem: Encodable {
    let itemKey:         String
    let name:            String
    let priceCents:      Int
    let vatRateInhouse:  String
    let vatRateTakeaway: String
    let visualKey:       String?
    let reviewConfirmed: Bool?
    let onNameCollision: String?   // "skip" | "create"

    // visualKey muss als JSON-null ankommen (Backend-Schema: nullable, nicht optional)
    enum CodingKeys: String, CodingKey {
        case itemKey, name, priceCents, vatRateInhouse, vatRateTakeaway,
             visualKey, reviewConfirmed, onNameCollision
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemKey, forKey: .itemKey)
        try c.encode(name, forKey: .name)
        try c.encode(priceCents, forKey: .priceCents)
        try c.encode(vatRateInhouse, forKey: .vatRateInhouse)
        try c.encode(vatRateTakeaway, forKey: .vatRateTakeaway)
        try c.encode(visualKey, forKey: .visualKey)
        try c.encodeIfPresent(reviewConfirmed, forKey: .reviewConfirmed)
        try c.encodeIfPresent(onNameCollision, forKey: .onNameCollision)
    }
}

struct PresetImportBody: Encodable {
    let presetId:        String
    let presetVersion:   Int
    let taxBasisVersion: String
    let vatConfirmed:    Bool
    let items:           [PresetImportItem]
}

struct PresetImportResult: Decodable {
    struct Counts: Decodable {
        let categories: Int
        let products:   Int
    }
    struct Skipped: Decodable {
        let itemKey: String
        let reason:  String
    }
    let importId: Int
    let imported: Counts
    let skipped:  [Skipped]
}

// ── Wizard-Bestätigungslogik (pure, unit-getestet) ───────────────────────────
// §2.3: Auch grüne Standardzeilen werden nie still übernommen; recipe_review/
// printed_price_review dürfen NICHT über die Sammelbestätigung erledigt werden.

struct WizardReviewState {
    /// Sammelbestätigung „Sätze geprüft" für Standard-/Speisenzeilen
    var bulkConfirmed = false
    /// Einzelbestätigungen je item_key (nur Risikozeilen)
    var individuallyConfirmed: Set<String> = []

    /// Bestätigt eine Risikozeile einzeln.
    mutating func confirmIndividually(_ itemKey: String) {
        individuallyConfirmed.insert(itemKey)
    }

    /// Die Sammelbestätigung wirkt ausdrücklich NUR auf Nicht-Risikozeilen.
    func isConfirmed(_ product: PresetProduct) -> Bool {
        product.needsIndividualReview
            ? individuallyConfirmed.contains(product.itemKey)
            : bulkConfirmed
    }

    /// Import erst zulässig, wenn ALLE ausgewählten Zeilen bestätigt sind.
    func allConfirmed(selected: [PresetProduct]) -> Bool {
        selected.allSatisfy { isConfirmed($0) }
    }
}

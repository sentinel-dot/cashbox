// PresetDecodingTests.swift — TC-IOS / REQ-PRESET: GET /products/presets
// (wörtliche snake_case-Fixtures) + Fehlertoleranz für unbekannte visual_keys.

import XCTest
@testable import zettel_frontend

final class PresetDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.cashbox.decode(T.self, from: Data(json.utf8))
    }

    // Wörtliches Fixture im Wire-Format: gekürztes Späti-Preset mit allen
    // Zeilentypen (standard, Pfand-gesperrt, Tabakvorlage) + leeres Preset
    private let presetsJson = """
    [
      {
        "preset_id": "spaeti", "display_name": "Späti", "version": 1,
        "tax_basis_version": "de-ust-2026-01",
        "categories": [
          { "category_key": "cold_drinks", "name_de": "Alkoholfreie Getränke",
            "sort_order": 10, "color_role": "blue", "color": "#3a7ca5" },
          { "category_key": "tobacco", "name_de": "Tabak",
            "sort_order": 50, "color_role": "brown", "color": "#8a5a2b" }
        ],
        "products": [
          { "item_key": "orange_juice_carton_100", "category_key": "cold_drinks",
            "name_de": "Orangensaft, Karton 1,0 l", "sort_order": 80, "price_cents": null,
            "vat_rate_inhouse": "19", "vat_rate_takeaway": "19", "vat_review": "standard_19",
            "visual_key": "juice", "deposit_cents": 0 },
          { "item_key": "cola_can_033", "category_key": "cold_drinks",
            "name_de": "Cola, Dose 0,33 l", "sort_order": 30, "price_cents": null,
            "vat_rate_inhouse": "19", "vat_rate_takeaway": "19", "vat_review": "standard_19",
            "visual_key": "soft_drink", "deposit_cents": 25 },
          { "item_key": "cigarettes_custom", "category_key": "tobacco",
            "name_de": "Zigaretten (Vorlage)", "sort_order": 10, "price_cents": null,
            "vat_rate_inhouse": "19", "vat_rate_takeaway": "19", "vat_review": "printed_price_review",
            "visual_key": "cigarettes", "deposit_cents": 0,
            "requires_custom_name": true, "requires_exact_price": true }
        ]
      },
      {
        "preset_id": "empty", "display_name": "Leer starten", "version": 1,
        "tax_basis_version": "de-ust-2026-01", "categories": [], "products": []
      }
    ]
    """

    func testPresetListDecoding() throws {
        let presets = try decode([AssortmentPreset].self, presetsJson)
        XCTAssertEqual(presets.count, 2)

        let spaeti = presets[0]
        XCTAssertEqual(spaeti.presetId, "spaeti")
        XCTAssertEqual(spaeti.taxBasisVersion, "de-ust-2026-01")
        XCTAssertEqual(spaeti.categories[0].color, "#3a7ca5")

        let juice = spaeti.products[0]
        XCTAssertFalse(juice.isDepositBlocked)
        XCTAssertFalse(juice.isTemplate)
        XCTAssertFalse(juice.needsIndividualReview)

        let cola = spaeti.products[1]
        XCTAssertTrue(cola.isDepositBlocked)

        let cigarettes = spaeti.products[2]
        XCTAssertTrue(cigarettes.isTemplate)
        XCTAssertTrue(cigarettes.needsIndividualReview)

        // readyProducts: ohne Vorlage und ohne Pfand-Zeile
        XCTAssertEqual(spaeti.readyProducts.map(\.itemKey), ["orange_juice_carton_100"])

        XCTAssertEqual(presets[1].products.count, 0)
    }

    func testUnbekannterVisualKeyUndVatReview_brechenNichtsAb() throws {
        // Neuere API-Version: unbekannte Strings dürfen kein Decode-Fehler sein
        let json = presetsJson
            .replacingOccurrences(of: "\"visual_key\": \"juice\"", with: "\"visual_key\": \"zukunfts_motiv_2027\"")
            .replacingOccurrences(of: "\"vat_review\": \"standard_19\"", with: "\"vat_review\": \"neue_klasse\"")
        let presets = try decode([AssortmentPreset].self, json)
        XCTAssertEqual(presets[0].products[0].visualKey, "zukunfts_motiv_2027")
        // Unbekannte Klasse ⇒ konservativ KEINE Einzelbestätigungs-Klasse,
        // aber der Katalog rendert das Visual defensiv als generic
        XCTAssertNotNil(ProduktVisualCatalog.visual(for: "zukunfts_motiv_2027"))
    }

    func testProductMitUnbekanntemVisualKey_decodiertUndFaelltZurueck() throws {
        let json = """
        {
          "id": 7, "name": "Neu", "price_cents": 100,
          "vat_rate_inhouse": "19", "vat_rate_takeaway": "19",
          "is_active": true, "sort_order": 10, "visual_key": "hologramm_2030",
          "created_at": "2026-07-21T10:00:00.000Z", "category": null, "modifier_groups": []
        }
        """
        let product = try JSONDecoder.cashbox.decode(Product.self, from: Data(json.utf8))
        XCTAssertEqual(product.visualKey, "hologramm_2030")
        if case .symbol(let name)? = ProduktVisualCatalog.visual(for: product.visualKey) {
            XCTAssertEqual(name, "square.grid.2x2.fill")   // generic-Fallback
        } else {
            XCTFail("Unbekannter Key muss als generic-Symbol rendern")
        }
    }

    func testImportBodyEncoding_visualKeyNullBleibtErhalten() throws {
        let item = PresetImportItem(
            itemKey: "espresso", name: "Espresso", priceCents: 280,
            vatRateInhouse: "19", vatRateTakeaway: "19",
            visualKey: nil, reviewConfirmed: nil, onNameCollision: nil
        )
        let data = try JSONEncoder.cashbox.encode(item)
        let json = String(data: data, encoding: .utf8)!
        // Backend-Schema: visual_key ist nullable, nicht optional — null muss ankommen
        XCTAssertTrue(json.contains("\"visual_key\":null"))
        XCTAssertFalse(json.contains("review_confirmed"))
    }
}

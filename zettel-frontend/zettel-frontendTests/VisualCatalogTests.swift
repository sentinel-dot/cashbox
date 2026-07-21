// VisualCatalogTests.swift — TC-IOS / REQ-PRESET: der V1-Katalog ist exhaustiv
// (39 Keys), deterministisch geordnet und fällt für nil/unbekannt korrekt zurück.

import XCTest
@testable import zettel_frontend

final class VisualCatalogTests: XCTestCase {

    func testKatalogEnthaelt39Keys() {
        XCTAssertEqual(ProduktVisualCatalog.catalog.count, 39)
        XCTAssertEqual(ProduktVisualCatalog.orderedKeys.count, 39)
        XCTAssertEqual(Set(ProduktVisualCatalog.orderedKeys), Set(ProduktVisualCatalog.catalog.keys))
    }

    func testJederKeyLiefertVisualUndLabel() {
        for key in ProduktVisualCatalog.orderedKeys {
            XCTAssertNotNil(ProduktVisualCatalog.visual(for: key), "Kein Visual für \(key)")
            let label = ProduktVisualCatalog.label(for: key)
            XCTAssertFalse(label.isEmpty)
            // §6.5: der technische Key wird nie als Label verwendet
            XCTAssertNotEqual(label, key)
        }
    }

    func testNilRendertTextkachel() {
        XCTAssertNil(ProduktVisualCatalog.visual(for: nil))
        XCTAssertEqual(ProduktVisualCatalog.label(for: nil), "Ohne Symbol")
    }

    func testUnbekannterKeyFaelltAufGenericZurueck() {
        guard case .symbol(let name)? = ProduktVisualCatalog.visual(for: "gibt_es_nicht") else {
            return XCTFail("Unbekannter Key muss generic liefern")
        }
        XCTAssertEqual(name, "square.grid.2x2.fill")
        XCTAssertEqual(ProduktVisualCatalog.label(for: "gibt_es_nicht"), "Allgemein")
    }

    func testBundleAssetKeysDefiniert() {
        // Die vier V1-Assets aus der Spec (§6.3)
        let assetKeys = ["shisha", "shisha_refill", "croissant", "pretzel"]
        for key in assetKeys {
            guard case .asset(let name)? = ProduktVisualCatalog.catalog[key]?.visual else {
                return XCTFail("\(key) muss ein Bundle-Asset sein")
            }
            XCTAssertTrue(name.hasPrefix("product."))
            // Asset existiert im Bundle — sonst greift zur Laufzeit der generic-Fallback
            XCTAssertNotNil(UIImage(named: name), "Bundle-Asset \(name) fehlt")
        }
    }
}

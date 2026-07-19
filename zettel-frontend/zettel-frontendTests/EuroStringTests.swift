// EuroStringTests.swift
// TC-IOS / REQ-UX-002: Cent → deutsche Betragsanzeige (euroString, DesignSystem.swift)

import XCTest
@testable import zettel_frontend

final class EuroStringTests: XCTestCase {

    func testNull() {
        XCTAssertEqual(euroString(0), "0,00 €")
    }

    func testStandardBetrag() {
        XCTAssertEqual(euroString(1250), "12,50 €")
    }

    func testTausenderpunkt() {
        XCTAssertEqual(euroString(123456), "1.234,56 €")
    }

    func testNegativerBetrag_StornoAnzeige() {
        XCTAssertEqual(euroString(-1250), "-12,50 €")
    }

    func testEinCent() {
        XCTAssertEqual(euroString(1), "0,01 €")
    }

    func testKrummerBetrag_keineFloatArtefakte() {
        // 19,99 € und Verwandte sind klassische Binär-Float-Fallen
        XCTAssertEqual(euroString(1999), "19,99 €")
        XCTAssertEqual(euroString(2849), "28,49 €")
    }

    func testRoundtripMitParseCents() {
        for cents in [0, 1, 99, 100, 1250, 1999, 123456] {
            let formatted = euroString(cents)
            XCTAssertEqual(parseCents(formatted), cents, "Roundtrip für \(cents) Cent")
        }
    }

    func testAccessibilityLabel() {
        XCTAssertEqual(euroAccessibilityLabel(2350), "23 Euro 50")
        XCTAssertEqual(euroAccessibilityLabel(2000), "20 Euro")
        XCTAssertEqual(euroAccessibilityLabel(-1250), "minus 12 Euro 50")
    }
}

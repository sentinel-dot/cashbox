// ParseCentsTests.swift
// TC-IOS / REQ-UX-002: deutsche Betragseingabe → Cent (parseCents, DesignSystem.swift)

import XCTest
@testable import zettel_frontend

final class ParseCentsTests: XCTestCase {

    func testKommaEingabe() {
        XCTAssertEqual(parseCents("12,50"), 1250)
    }

    func testPunktEingabe() {
        XCTAssertEqual(parseCents("12.50"), 1250)
    }

    func testEuroZeichenUndWhitespaceWerdenGestrippt() {
        XCTAssertEqual(parseCents(" 19,99 € "), 1999)
    }

    func testTruncateRegression_1999() {
        // 19.99 × 100 = 1998.99… — ohne .rounded() würde Int() 1998 abschneiden
        XCTAssertEqual(parseCents("19,99"), 1999)
    }

    func testGanzzahlOhneNachkommastellen() {
        XCTAssertEqual(parseCents("25"), 2500)
    }

    func testNullIstGueltig() {
        XCTAssertEqual(parseCents("0"), 0)
    }

    func testEinCent() {
        XCTAssertEqual(parseCents("0,01"), 1)
    }

    func testLeereEingabeIstNil() {
        XCTAssertNil(parseCents(""))
        XCTAssertNil(parseCents("   "))
    }

    func testUnlesbareEingabeIstNil() {
        XCTAssertNil(parseCents("abc"))
        XCTAssertNil(parseCents("12,5x"))
    }

    func testNegativeEingabeIstNil() {
        // Kein negativer Kassenbestand / Produktpreis über Eingabefelder
        XCTAssertNil(parseCents("-5"))
        XCTAssertNil(parseCents("-0,01"))
    }

    func testGrosserBetrag() {
        XCTAssertEqual(parseCents("1234,56"), 123456)
    }

    func testTausenderpunktMitKomma() {
        // Roundtrip-Fund (euroString formatiert "1.234,56 €"): Punkte sind
        // bei vorhandenem Komma Tausendertrenner, kein Dezimaltrenner
        XCTAssertEqual(parseCents("1.234,56"), 123456)
        XCTAssertEqual(parseCents("1.234,56 €"), 123456)
    }
}

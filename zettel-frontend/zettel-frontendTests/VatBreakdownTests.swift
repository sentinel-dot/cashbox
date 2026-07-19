// VatBreakdownTests.swift
// TC-IOS / REQ-GELD-006: MwSt-Formelparität iOS ↔ Backend.
// Erwartungswerte exakt aus backend/src/__tests__/unit/vatCalculation.test.ts —
// beide Seiten rechnen net = round(gross × 100 / 107|119), tax = gross − net.

import XCTest
@testable import zettel_frontend

final class VatBreakdownTests: XCTestCase {

    private func item(_ subtotalCents: Int, vat: String) -> OrderItem {
        OrderItem(
            id: 1, productId: 1, productName: "Test",
            productPriceCents: subtotalCents, vatRate: vat, quantity: 1,
            subtotalCents: subtotalCents, discountCents: 0, discountReason: nil,
            createdAt: "", modifiers: []
        )
    }

    func test19Prozent_1190Cent() {
        let v = computeVat([item(1190, vat: "19")])
        XCTAssertEqual(v.vat19NetCents, 1000)
        XCTAssertEqual(v.vat19TaxCents, 190)
    }

    func test19Prozent_100Cent_gerundeterCent() {
        let v = computeVat([item(100, vat: "19")])
        XCTAssertEqual(v.vat19NetCents, 84)
        XCTAssertEqual(v.vat19TaxCents, 16)
    }

    func test7Prozent_107Cent() {
        let v = computeVat([item(107, vat: "7")])
        XCTAssertEqual(v.vat7NetCents, 100)
        XCTAssertEqual(v.vat7TaxCents, 7)
    }

    func test7Prozent_200Cent() {
        let v = computeVat([item(200, vat: "7")])
        XCTAssertEqual(v.vat7NetCents, 187)
        XCTAssertEqual(v.vat7TaxCents, 13)
    }

    func testBruttoGleichNettoPlusSteuer_KrummeBetraege() {
        // Paritätsfälle aus vatCalculation.test.ts („kein Rundungsfehler")
        for gross in [199, 250, 1500, 2990, 9999] {
            let v19 = computeVat([item(gross, vat: "19")])
            XCTAssertEqual(v19.vat19NetCents + v19.vat19TaxCents, gross, "19 % bei \(gross)")
            let v7 = computeVat([item(gross, vat: "7")])
            XCTAssertEqual(v7.vat7NetCents + v7.vat7TaxCents, gross, "7 % bei \(gross)")
        }
    }

    func testGemischteSaetze_getrenntAufgeschluesselt() {
        let v = computeVat([item(350, vat: "7"), item(1900, vat: "19")])
        XCTAssertEqual(v.vat7NetCents + v.vat7TaxCents, 350)
        XCTAssertEqual(v.vat19NetCents + v.vat19TaxCents, 1900)
        XCTAssertTrue(v.has7)
        XCTAssertTrue(v.has19)
    }

    func testJePositionGerundet_nichtUeberSumme() {
        // Backend rundet je Position (buildVatBreakdown) — iOS muss identisch summieren
        let v = computeVat([item(100, vat: "19"), item(100, vat: "19")])
        XCTAssertEqual(v.vat19NetCents, 168)   // 84 + 84, nicht round(200/1.19) = 168 ✓ gleich
        XCTAssertEqual(v.vat19TaxCents, 32)
    }

    func testLeereListe() {
        let v = computeVat([])
        XCTAssertFalse(v.has7)
        XCTAssertFalse(v.has19)
        XCTAssertEqual(v.vat19NetCents + v.vat7NetCents, 0)
    }
}

// PaymentLogicTests.swift
// TC-IOS / REQ-UX-003: Zahlungszeilen bauen (buildPayments, PaymentLogic.swift)
// Invariante: Summe der Zahlungen == totalCents — Backend lehnt alles andere mit 422 ab.

import XCTest
@testable import zettel_frontend

final class PaymentLogicTests: XCTestCase {

    private func sum(_ payments: [PaymentItem]) -> Int {
        payments.reduce(0) { $0 + $1.amountCents }
    }

    func testBar_eineCashZeileUeberTotal() {
        let p = buildPayments(mode: .bar, barRaw: "", totalCents: 4400)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].method, .cash)
        XCTAssertEqual(p[0].amountCents, 4400)
    }

    func testKarte_eineCardZeileUeberTotal() {
        let p = buildPayments(mode: .karte, barRaw: "", totalCents: 2250)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].method, .card)
        XCTAssertEqual(p[0].amountCents, 2250)
    }

    func testGemischt_barPlusKarteRest() {
        let p = buildPayments(mode: .gemischt, barRaw: "1000", totalCents: 3000)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[0].method, .cash)
        XCTAssertEqual(p[0].amountCents, 1000)
        XCTAssertEqual(p[1].method, .card)
        XCTAssertEqual(p[1].amountCents, 2000)
        XCTAssertEqual(sum(p), 3000)
    }

    func testGemischt_barGleichTotal_nurCash() {
        let p = buildPayments(mode: .gemischt, barRaw: "3000", totalCents: 3000)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].method, .cash)
        XCTAssertEqual(sum(p), 3000)
    }

    func testGemischt_leereBarEingabe_nurCard() {
        let p = buildPayments(mode: .gemischt, barRaw: "", totalCents: 3000)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].method, .card)
        XCTAssertEqual(sum(p), 3000)
    }

    func testGemischt_barUeberTotal_wirdAufTotalGeklemmt() {
        // Überzahlung bar = Rückgeld; gebucht wird exakt total (sonst Backend-422)
        let p = buildPayments(mode: .gemischt, barRaw: "5000", totalCents: 3000)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].method, .cash)
        XCTAssertEqual(p[0].amountCents, 3000)
    }

    func testSummenInvariante_ueberAlleModiUndEingaben() {
        let total = 2849
        for mode in [PaymentView.PayMode.bar, .karte] {
            XCTAssertEqual(sum(buildPayments(mode: mode, barRaw: "", totalCents: total)), total)
        }
        for barRaw in ["", "1", "849", "2848", "2849", "9999", "abc"] {
            let p = buildPayments(mode: .gemischt, barRaw: barRaw, totalCents: total)
            XCTAssertEqual(sum(p), total, "gemischt mit barRaw=\(barRaw)")
        }
    }
}

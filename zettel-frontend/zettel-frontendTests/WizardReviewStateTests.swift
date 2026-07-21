// WizardReviewStateTests.swift — TC-IOS / REQ-PRESET: Die Sammelbestätigung
// darf Risikozeilen (recipe_review/printed_price_review) NIEMALS miterledigen (§2.3).

import XCTest
@testable import zettel_frontend

final class WizardReviewStateTests: XCTestCase {

    private func product(_ key: String, review: String) -> PresetProduct {
        let json = """
        { "item_key": "\(key)", "category_key": "c", "name_de": "N", "sort_order": 10,
          "price_cents": null, "vat_rate_inhouse": "19", "vat_rate_takeaway": "19",
          "vat_review": "\(review)", "visual_key": null, "deposit_cents": 0 }
        """
        return try! JSONDecoder.cashbox.decode(PresetProduct.self, from: Data(json.utf8))
    }

    func testSammelbestaetigungDecktNurStandardzeilen() {
        let standard = product("espresso",   review: "standard_19")
        let food     = product("croissant",  review: "food_7_2026")
        let risk     = product("cappuccino", review: "recipe_review")

        var state = WizardReviewState()
        state.bulkConfirmed = true

        XCTAssertTrue(state.isConfirmed(standard))
        XCTAssertTrue(state.isConfirmed(food))
        // Risikozeile bleibt unbestätigt — Sammelaktion wirkt hier nicht
        XCTAssertFalse(state.isConfirmed(risk))
        XCTAssertFalse(state.allConfirmed(selected: [standard, food, risk]))
    }

    func testEinzelbestaetigungSchaltetNurDieseZeileFrei() {
        let riskA = product("cappuccino", review: "recipe_review")
        let riskB = product("cigarettes_custom", review: "printed_price_review")

        var state = WizardReviewState()
        state.bulkConfirmed = true
        state.confirmIndividually("cappuccino")

        XCTAssertTrue(state.isConfirmed(riskA))
        XCTAssertFalse(state.isConfirmed(riskB))
        XCTAssertFalse(state.allConfirmed(selected: [riskA, riskB]))

        state.confirmIndividually("cigarettes_custom")
        XCTAssertTrue(state.allConfirmed(selected: [riskA, riskB]))
    }

    func testOhneSammelbestaetigungBlocktAuchStandard() {
        let standard = product("espresso", review: "standard_19")
        var state = WizardReviewState()
        state.confirmIndividually("espresso")   // Einzelbestätigung ersetzt Sammel nicht
        XCTAssertFalse(state.isConfirmed(standard))
        XCTAssertFalse(state.allConfirmed(selected: [standard]))
    }

    func testLeereAuswahlIstBestaetigt() {
        let state = WizardReviewState()
        XCTAssertTrue(state.allConfirmed(selected: []))
    }
}

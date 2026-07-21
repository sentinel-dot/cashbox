// AssortmentSortTests.swift
// TC-IOS / REQ-SORT: assortmentSorted() muss exakt die Backend-Sortierung spiegeln:
// (Kategorie zuletzt wenn nil) → c.sort_order → c.name → p.sort_order → p.name → p.id

import XCTest
@testable import zettel_frontend

final class AssortmentSortTests: XCTestCase {

    private func cat(_ id: Int, _ name: String, _ sort: Int) -> ProductCategoryRef {
        ProductCategoryRef(id: id, name: name, color: nil, sortOrder: sort)
    }

    private func prod(
        _ id: Int, _ name: String, sort: Int, cat: ProductCategoryRef?
    ) -> Product {
        Product(
            id: id, name: name, priceCents: 100,
            vatRateInhouse: "19", vatRateTakeaway: "19",
            isActive: true, sortOrder: sort, visualKey: nil, createdAt: "",
            category: cat, modifierGroups: []
        )
    }

    func testKategorienNachSortOrder() {
        let spaet = cat(1, "A-Spät", 20)
        let frueh = cat(2, "Z-Früh", 10)
        let sorted = assortmentSorted([
            prod(1, "X", sort: 10, cat: spaet),
            prod(2, "Y", sort: 10, cat: frueh),
        ])
        // Kategorie-sort_order schlägt Kategorie-Name
        XCTAssertEqual(sorted.map(\.id), [2, 1])
    }

    func testKategorieNameAlsTieBreaker() {
        let b = cat(1, "Beta", 10)
        let a = cat(2, "Alpha", 10)
        let sorted = assortmentSorted([
            prod(1, "X", sort: 10, cat: b),
            prod(2, "Y", sort: 10, cat: a),
        ])
        XCTAssertEqual(sorted.map(\.id), [2, 1])
    }

    func testProdukteInnerhalbKategorieNachSortOrder() {
        let c = cat(1, "Kat", 10)
        let sorted = assortmentSorted([
            prod(1, "A-Spät", sort: 30, cat: c),
            prod(2, "Z-Früh", sort: 10, cat: c),
            prod(3, "M-Mitte", sort: 20, cat: c),
        ])
        XCTAssertEqual(sorted.map(\.id), [2, 3, 1])
    }

    func testProduktNameAlsTieBreaker() {
        let c = cat(1, "Kat", 10)
        let sorted = assortmentSorted([
            prod(1, "Beta",  sort: 10, cat: c),
            prod(2, "Alpha", sort: 10, cat: c),
        ])
        XCTAssertEqual(sorted.map(\.id), [2, 1])
    }

    func testIdAlsLetzterTieBreaker() {
        let c = cat(1, "Kat", 10)
        let sorted = assortmentSorted([
            prod(9, "Gleich", sort: 10, cat: c),
            prod(3, "Gleich", sort: 10, cat: c),
        ])
        XCTAssertEqual(sorted.map(\.id), [3, 9])
    }

    func testOhneKategorieZuletzt() {
        let c = cat(1, "Kat", 99)
        let sorted = assortmentSorted([
            prod(1, "Ohne", sort: 5, cat: nil),
            prod(2, "Mit",  sort: 50, cat: c),
        ])
        // Produkte ohne Kategorie kommen nach allen kategorisierten
        XCTAssertEqual(sorted.map(\.id), [2, 1])
    }

    func testOhneKategorieUntereinanderSortiert() {
        let sorted = assortmentSorted([
            prod(1, "B", sort: 20, cat: nil),
            prod(2, "A", sort: 10, cat: nil),
        ])
        XCTAssertEqual(sorted.map(\.id), [2, 1])
    }

    func testStabilBeiWiederholung() {
        let c1 = cat(1, "Erste", 10)
        let c2 = cat(2, "Zweite", 20)
        let input = [
            prod(4, "D", sort: 20, cat: c2),
            prod(1, "A", sort: 10, cat: c1),
            prod(3, "C", sort: 10, cat: c2),
            prod(2, "B", sort: 20, cat: c1),
        ]
        let once  = assortmentSorted(input)
        let twice = assortmentSorted(once)
        XCTAssertEqual(once.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(once.map(\.id), twice.map(\.id))
    }
}

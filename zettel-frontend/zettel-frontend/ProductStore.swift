// ProductStore.swift
// cashbox — Produktkatalog laden (inkl. Kategorien + Modifier-Gruppen)

import Foundation

@MainActor
final class ProductStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var products:      [Product]            = []
    @Published private(set) var categories:    [ProductCategoryRef] = []  // nur Kategorien mit mind. 1 Produkt
    @Published private(set) var allCategories: [ProductCategoryRef] = []  // alle Kategorien (für SortimentView)
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    /// - Parameter includeInactive: `true` = Management-Ansicht (Sortiment) inkl.
    ///   deaktivierter Produkte; Default `false` = Kassenansicht (nur aktive).
    func loadProducts(includeInactive: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let path = includeInactive ? "/products?include_inactive=1" : "/products"
            products = assortmentSorted(try await api.get(path))
            // Kategorien aus Produkten ableiten — Reihenfolge beibehalten, deduplizieren
            var seen = Set<Int>()
            categories = products
                .compactMap { $0.category }
                .filter { seen.insert($0.id).inserted }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Lädt alle Kategorien direkt (inkl. leerer Kategorien ohne Produkte)
    func loadCategories() async {
        do {
            allCategories = try await api.get("/products/categories")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Kassen-Pfad: liefert IMMER nur aktive Produkte — auch wenn der Store
    /// gerade die Management-Ansicht (inkl. inaktiver) geladen hat.
    func products(for categoryId: Int?) -> [Product] {
        let active = products.filter { $0.isActive }
        guard let id = categoryId else { return active }
        return active.filter { $0.category?.id == id }
    }

    // ── Produkt-CRUD ───────────────────────────────────────────────────────

    func createProduct(
        name: String, priceCents: Int,
        vatRateInhouse: String, vatRateTakeaway: String,
        categoryId: Int?, sortOrder: Int? = nil
    ) async throws {
        let body = CreateProductBody(
            name: name, priceCents: priceCents,
            vatRateInhouse: vatRateInhouse, vatRateTakeaway: vatRateTakeaway,
            categoryId: categoryId, sortOrder: sortOrder
        )
        let _: ProductIdResponse = try await api.post("/products", body: body)
        await loadProducts(includeInactive: true)
    }

    func updateProduct(id: Int, name: String? = nil, isActive: Bool? = nil, categoryId: Int? = nil) async throws {
        let body = UpdateProductBody(name: name, isActive: isActive, categoryId: categoryId)
        let _: OkResponse = try await api.patch("/products/\(id)", body: body)
        await loadProducts(includeInactive: true)
    }

    /// Preisänderung — erstellt einen product_price_history-Eintrag (GoBD: kein UPDATE auf price_cents)
    func changePrice(productId: Int, newPriceCents: Int) async throws {
        let body = ChangePriceBody(priceCents: newPriceCents)
        let _: EmptyResponse = try await api.post("/products/\(productId)/price", body: body)
        await loadProducts(includeInactive: true)
    }

    func deleteProduct(id: Int) async throws {
        try await api.delete("/products/\(id)")
        await loadProducts(includeInactive: true)
    }

    // ── Reorder (S17A) ─────────────────────────────────────────────────────

    /// Sendet die komplette geordnete ID-Liste einer Kategorie ans Backend.
    func reorderProducts(categoryId: Int?, orderedIds: [Int]) async throws {
        let body = ReorderProductsBody(categoryId: categoryId, productIds: orderedIds)
        let _: OkResponse = try await api.patch("/products/reorder", body: body)
        await loadProducts(includeInactive: true)
    }

    func reorderCategories(orderedIds: [Int]) async throws {
        let body = ReorderCategoriesBody(categoryIds: orderedIds)
        let _: OkResponse = try await api.patch("/products/categories/reorder", body: body)
        await loadCategories()
        await loadProducts(includeInactive: true)
    }

    // ── Kategorie-CRUD ─────────────────────────────────────────────────────

    func createCategory(name: String, color: String?, sortOrder: Int) async throws {
        let body = CreateCategoryBody(name: name, color: color, sortOrder: sortOrder)
        let _: ProductIdResponse = try await api.post("/products/categories", body: body)
        await loadCategories()
        await loadProducts(includeInactive: true)
    }

    func updateCategory(id: Int, name: String?, color: String?, sortOrder: Int?) async throws {
        let body = UpdateCategoryBody(name: name, color: color, sortOrder: sortOrder)
        let _: OkResponse = try await api.patch("/products/categories/\(id)", body: body)
        await loadCategories()
        await loadProducts(includeInactive: true)
    }

    func deleteCategory(id: Int) async throws {
        try await api.delete("/products/categories/\(id)")
        await loadCategories()
        await loadProducts(includeInactive: true)
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: ProductStore {
        let store = ProductStore()
        let cat1 = ProductCategoryRef(id: 1, name: "Getränke",  color: "#1a6fff", sortOrder: 10)
        let cat2 = ProductCategoryRef(id: 2, name: "Shisha",    color: "#9b59b6", sortOrder: 20)
        let cat3 = ProductCategoryRef(id: 3, name: "Snacks",    color: "#e67e22", sortOrder: 30)
        store.categories    = [cat1, cat2, cat3]
        store.allCategories = [cat1, cat2, cat3]

        let milchGroup = ModifierGroup(
            id: 1, productId: nil, categoryId: 1, name: "Milchart",
            isRequired: true, minSelections: 1, maxSelections: 1, sortOrder: 0,
            options: [
                ModifierOption(id: 1, name: "Vollmilch",    priceDeltaCents: 0,  sortOrder: 0),
                ModifierOption(id: 2, name: "Hafermilch",   priceDeltaCents: 50, sortOrder: 1),
                ModifierOption(id: 3, name: "Sojamilch",    priceDeltaCents: 50, sortOrder: 2),
            ]
        )
        let tabakGroup = ModifierGroup(
            id: 2, productId: nil, categoryId: 2, name: "Tabak",
            isRequired: true, minSelections: 1, maxSelections: 1, sortOrder: 0,
            options: [
                ModifierOption(id: 4, name: "Double Apple",  priceDeltaCents: 0,   sortOrder: 0),
                ModifierOption(id: 5, name: "Blaubeere",     priceDeltaCents: 0,   sortOrder: 1),
                ModifierOption(id: 6, name: "Premium Blend", priceDeltaCents: 500, sortOrder: 2),
            ]
        )

        store.products = [
            Product(id: 1,  name: "Cappuccino",      priceCents: 350,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, sortOrder: 10, createdAt: "", category: cat1, modifierGroups: [milchGroup]),
            Product(id: 2,  name: "Latte Macchiato", priceCents: 420,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, sortOrder: 20, createdAt: "", category: cat1, modifierGroups: [milchGroup]),
            Product(id: 3,  name: "Espresso",        priceCents: 280,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, sortOrder: 30, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 4,  name: "Ayran",            priceCents: 250,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, sortOrder: 40, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 5,  name: "Wasser 0,5l",      priceCents: 200,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, sortOrder: 50, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 6,  name: "Shisha Miete",     priceCents: 1500, vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, sortOrder: 60, createdAt: "", category: cat2, modifierGroups: [tabakGroup]),
            Product(id: 7,  name: "Kohle Extra",      priceCents: 300,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, sortOrder: 70, createdAt: "", category: cat2, modifierGroups: []),
            Product(id: 8,  name: "Chips",            priceCents: 200,  vatRateInhouse: "7",  vatRateTakeaway: "7",  isActive: true, sortOrder: 80, createdAt: "", category: cat3, modifierGroups: []),
            Product(id: 9,  name: "Nüsse",            priceCents: 250,  vatRateInhouse: "7",  vatRateTakeaway: "7",  isActive: true, sortOrder: 90, createdAt: "", category: cat3, modifierGroups: []),
        ]
        return store
    }

    static var previewEmpty: ProductStore { ProductStore() }
}

// MARK: - Request Bodies (privat)

private struct CreateProductBody: Encodable {
    let name:            String
    let priceCents:      Int
    let vatRateInhouse:  String
    let vatRateTakeaway: String
    let categoryId:      Int?
    let sortOrder:       Int?
}

private struct UpdateProductBody: Encodable {
    let name:       String?
    let isActive:   Bool?
    let categoryId: Int?
}

private struct ReorderProductsBody: Encodable {
    let categoryId: Int?
    let productIds: [Int]

    // categoryId = nil bedeutet „Produkte ohne Kategorie" und muss als
    // JSON-null ankommen — encodeIfPresent würde den Key weglassen (422 im Backend).
    enum CodingKeys: String, CodingKey { case categoryId, productIds }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(productIds, forKey: .productIds)
    }
}

private struct ReorderCategoriesBody: Encodable {
    let categoryIds: [Int]
}

private struct ChangePriceBody: Encodable {
    let priceCents: Int
}

private struct ProductIdResponse: Decodable {
    let id: Int
}

private struct CreateCategoryBody: Encodable {
    let name:      String
    let color:     String?
    let sortOrder: Int
}

private struct UpdateCategoryBody: Encodable {
    let name:      String?
    let color:     String?
    let sortOrder: Int?
}

// MARK: - Helpers

private extension Array where Element == ProductCategoryRef {
    func uniqued() -> [ProductCategoryRef] {
        var seen = Set<Int>()
        return filter { seen.insert($0.id).inserted }
    }
}

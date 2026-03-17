// ProductStore.swift
// cashbox — Produktkatalog laden (inkl. Kategorien + Modifier-Gruppen)

import Foundation

@MainActor
final class ProductStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var products:      [Product]            = []
    @Published private(set) var categories:    [ProductCategoryRef] = []  // nur Kategorien mit mind. 1 Produkt
    @Published private(set) var allCategories: [ProductCategoryRef] = []  // alle Kategorien (für KategorienView)
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await api.get("/products")
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

    func products(for categoryId: Int?) -> [Product] {
        guard let id = categoryId else { return products }
        return products.filter { $0.category?.id == id }
    }

    // ── Produkt-CRUD ───────────────────────────────────────────────────────

    func createProduct(
        name: String, priceCents: Int,
        vatRateInhouse: String, vatRateTakeaway: String,
        categoryId: Int?
    ) async throws {
        let body = CreateProductBody(
            name: name, priceCents: priceCents,
            vatRateInhouse: vatRateInhouse, vatRateTakeaway: vatRateTakeaway,
            categoryId: categoryId
        )
        let _: ProductIdResponse = try await api.post("/products", body: body)
        await loadProducts()
    }

    func updateProduct(id: Int, name: String?, vatRateInhouse: String?, isActive: Bool?, categoryId: Int?) async throws {
        let body = UpdateProductBody(name: name, vatRateInhouse: vatRateInhouse, isActive: isActive, categoryId: categoryId)
        let _: OkResponse = try await api.patch("/products/\(id)", body: body)
        await loadProducts()
    }

    /// Preisänderung — erstellt einen product_price_history-Eintrag (GoBD: kein UPDATE auf price_cents)
    func changePrice(productId: Int, newPriceCents: Int, reason: String) async throws {
        let body = ChangePriceBody(priceCents: newPriceCents)
        let _: EmptyResponse = try await api.post("/products/\(productId)/price", body: body)
        await loadProducts()
    }

    func deleteProduct(id: Int) async throws {
        try await api.delete("/products/\(id)")
        products.removeAll { $0.id == id }
        categories = products.compactMap { $0.category }.uniqued()
    }

    // ── Kategorie-CRUD ─────────────────────────────────────────────────────

    func createCategory(name: String, color: String?, sortOrder: Int) async throws {
        let body = CreateCategoryBody(name: name, color: color, sortOrder: sortOrder)
        let _: ProductIdResponse = try await api.post("/products/categories", body: body)
        await loadCategories()
        await loadProducts()
    }

    func updateCategory(id: Int, name: String?, color: String?, sortOrder: Int?) async throws {
        let body = UpdateCategoryBody(name: name, color: color, sortOrder: sortOrder)
        let _: OkResponse = try await api.patch("/products/categories/\(id)", body: body)
        await loadCategories()
        await loadProducts()
    }

    func deleteCategory(id: Int) async throws {
        try await api.delete("/products/categories/\(id)")
        await loadCategories()
        await loadProducts()
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: ProductStore {
        let store = ProductStore()
        let cat1 = ProductCategoryRef(id: 1, name: "Getränke",  color: "#1a6fff")
        let cat2 = ProductCategoryRef(id: 2, name: "Shisha",    color: "#9b59b6")
        let cat3 = ProductCategoryRef(id: 3, name: "Snacks",    color: "#e67e22")
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
            Product(id: 1,  name: "Cappuccino",      priceCents: 350,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, createdAt: "", category: cat1, modifierGroups: [milchGroup]),
            Product(id: 2,  name: "Latte Macchiato", priceCents: 420,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, createdAt: "", category: cat1, modifierGroups: [milchGroup]),
            Product(id: 3,  name: "Espresso",        priceCents: 280,  vatRateInhouse: "19", vatRateTakeaway: "7",  isActive: true, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 4,  name: "Ayran",            priceCents: 250,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 5,  name: "Wasser 0,5l",      priceCents: 200,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, createdAt: "", category: cat1, modifierGroups: []),
            Product(id: 6,  name: "Shisha Miete",     priceCents: 1500, vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, createdAt: "", category: cat2, modifierGroups: [tabakGroup]),
            Product(id: 7,  name: "Kohle Extra",      priceCents: 300,  vatRateInhouse: "19", vatRateTakeaway: "19", isActive: true, createdAt: "", category: cat2, modifierGroups: []),
            Product(id: 8,  name: "Chips",            priceCents: 200,  vatRateInhouse: "7",  vatRateTakeaway: "7",  isActive: true, createdAt: "", category: cat3, modifierGroups: []),
            Product(id: 9,  name: "Nüsse",            priceCents: 250,  vatRateInhouse: "7",  vatRateTakeaway: "7",  isActive: true, createdAt: "", category: cat3, modifierGroups: []),
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
}

private struct UpdateProductBody: Encodable {
    let name:           String?
    let vatRateInhouse: String?
    let isActive:       Bool?
    let categoryId:     Int?
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

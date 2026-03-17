// OrderStore.swift
// cashbox — Bestellungen der aktuellen Session: laden, erstellen, Items, Storno

import Foundation

@MainActor
final class OrderStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var orders: [Order] = []
    @Published private(set) var selectedOrder: OrderDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    /// Lädt alle offenen Bestellungen der aktuellen Session.
    func loadOrders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            orders = try await api.get("/orders")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Erstellt eine neue Bestellung (optional mit Tisch).
    @discardableResult
    func createOrder(tableId: Int? = nil) async throws -> Order {
        let body = CreateOrderBody(tableId: tableId)
        let created: CreateOrderResponse = try await api.post("/orders", body: body)
        await loadOrders()
        // Gib die frisch geladene Order zurück, oder konstruiere aus Response
        return orders.first(where: { $0.id == created.id })
            ?? Order(id: created.id, status: .open, isTakeaway: false,
                     createdAt: "", openedByName: "", table: nil)
    }

    /// Lädt eine einzelne Bestellung mit allen Items.
    func loadOrder(_ id: Int) async throws {
        isLoading = true
        defer { isLoading = false }
        selectedOrder = try await api.get("/orders/\(id)")
    }

    /// Fügt ein Produkt zur Bestellung hinzu.
    func addItem(
        orderId: Int,
        productId: Int,
        quantity: Int = 1,
        modifierOptionIds: [Int] = [],
        discountCents: Int = 0,
        discountReason: String? = nil
    ) async throws {
        let body = AddItemBody(
            productId: productId,
            quantity: quantity,
            modifierOptionIds: modifierOptionIds.isEmpty ? nil : modifierOptionIds,
            discountCents: discountCents > 0 ? discountCents : nil,
            discountReason: discountReason
        )
        let _: AddItemResponse = try await api.post("/orders/\(orderId)/items", body: body)
        try await loadOrder(orderId)
    }

    /// Entfernt eine Position aus der Bestellung (GoBD-konform via order_item_removals).
    func removeItem(orderId: Int, itemId: Int) async throws {
        try await api.delete("/orders/\(orderId)/items/\(itemId)")
        try await loadOrder(orderId)
    }

    /// Storniert eine offene Bestellung (noch kein Bon).
    func cancelOrder(_ id: Int, reason: String) async throws {
        let body = CancelOrderBody(reason: reason)
        let _: EmptyResponse = try await api.post("/orders/\(id)/cancel", body: body)
        orders.removeAll(where: { $0.id == id })
        if selectedOrder?.id == id { selectedOrder = nil }
    }

    /// Bezahlt eine Bestellung (Bar, Karte oder Gemischt). Gibt PaymentResult zurück.
    func pay(orderId: Int, payments: [PaymentItem]) async throws -> PaymentResult {
        let body = PayOrderBody(payments: payments.map {
            PaymentItemBody(method: $0.method.rawValue, amountCents: $0.amountCents)
        })
        let result: PaymentResult = try await api.post("/orders/\(orderId)/pay", body: body)
        orders.removeAll { $0.id == orderId }
        selectedOrder = nil
        return result
    }

    func clearError() { error = nil }
    func clearSelection() { selectedOrder = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: OrderStore {
        let store = OrderStore()
        store.orders = [
            Order(id: 1, status: .open, isTakeaway: false,
                  createdAt: "2026-03-16T10:00:00.000Z",
                  openedByName: "Niko",
                  table: OrderTable(id: 3, name: "Tisch 3")),
            Order(id: 2, status: .open, isTakeaway: false,
                  createdAt: "2026-03-16T10:15:00.000Z",
                  openedByName: "Niko",
                  table: nil),
        ]
        return store
    }

    static var previewEmpty: OrderStore {
        OrderStore()
    }
}

// MARK: - Request Bodies (privat)

private struct CreateOrderBody: Encodable {
    let tableId: Int?
}

private struct CreateOrderResponse: Decodable {
    let id: Int
    let status: String
}

private struct AddItemBody: Encodable {
    let productId: Int
    let quantity: Int
    let modifierOptionIds: [Int]?
    let discountCents: Int?
    let discountReason: String?
}

private struct AddItemResponse: Decodable {
    let id: Int
    let productName: String
    let subtotalCents: Int
}

private struct CancelOrderBody: Encodable {
    let reason: String
}

private struct PayOrderBody: Encodable {
    let payments: [PaymentItemBody]
}

private struct PaymentItemBody: Encodable {
    let method:      String
    let amountCents: Int
}

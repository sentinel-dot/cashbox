// TableStore.swift
// cashbox — Tischliste + Zonen laden, CRUD

import Foundation

// ── CRUD Request/Response Bodies ───────────────────────────────────────────

private struct CreateZoneBody: Encodable {
    let name: String
    let sortOrder: Int
}

private struct CreateZoneResponse: Decodable {
    let id: Int
}

private struct CreateTableBody: Encodable {
    let name: String
    let zoneId: Int?
}

private struct CreateTableResponse: Decodable {
    let id: Int
}

@MainActor
final class TableStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var tables: [TableItem] = []
    @Published private(set) var zones:  [TableZone] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Computed ───────────────────────────────────────────────────────────
    var occupiedCount: Int { tables.filter { $0.openOrdersCount > 0 }.count }

    // ── Public Interface ───────────────────────────────────────────────────

    func loadTables() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Zonen + Tische parallel laden — Zonen per eigenem Endpoint damit
            // leere Zonen (ohne Tische) sofort sichtbar sind
            async let fetchedZones:  [TableZone] = api.get("/tables/zones")
            async let fetchedTables: [TableItem] = api.get("/tables")
            zones  = try await fetchedZones.sorted { $0.sortOrder < $1.sortOrder }
            tables = try await fetchedTables
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func clearError() { error = nil }

    // ── CRUD ───────────────────────────────────────────────────────────────

    func createZone(name: String, sortOrder: Int = 0) async throws {
        let body = CreateZoneBody(name: name, sortOrder: sortOrder)
        let _: CreateZoneResponse = try await api.post("/tables/zones", body: body)
        await loadTables()
    }

    func createTable(name: String, zoneId: Int?) async throws {
        let body = CreateTableBody(name: name, zoneId: zoneId)
        let _: CreateTableResponse = try await api.post("/tables", body: body)
        await loadTables()
    }

    func deleteTable(id: Int) async throws {
        try await api.delete("/tables/\(id)")
        await loadTables()
    }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: TableStore {
        let store = TableStore()
        let innen = TableZone(id: 1, name: "Innen", sortOrder: 0)
        let bar   = TableZone(id: 2, name: "Bar",   sortOrder: 1)
        store.zones = [innen, bar]
        store.tables = [
            TableItem(id: 1, name: "Tisch 1",    isActive: true, openOrdersCount: 2, totalOpenCents: 4250,  totalOpenItems: 4, oldestOrderAt: "2026-03-17T06:22:00.000Z", zone: innen),
            TableItem(id: 2, name: "Tisch 2",    isActive: true, openOrdersCount: 0, totalOpenCents: 0,     totalOpenItems: 0, oldestOrderAt: nil,                        zone: innen),
            TableItem(id: 3, name: "Tisch 3",    isActive: true, openOrdersCount: 1, totalOpenCents: 1800,  totalOpenItems: 2, oldestOrderAt: "2026-03-17T07:39:00.000Z", zone: innen),
            TableItem(id: 4, name: "Tisch 4",    isActive: true, openOrdersCount: 0, totalOpenCents: 0,     totalOpenItems: 0, oldestOrderAt: nil,                        zone: innen),
            TableItem(id: 5, name: "Bar 1",      isActive: true, openOrdersCount: 3, totalOpenCents: 8950,  totalOpenItems: 6, oldestOrderAt: "2026-03-17T06:48:00.000Z", zone: bar),
            TableItem(id: 6, name: "Bar 2",      isActive: true, openOrdersCount: 0, totalOpenCents: 0,     totalOpenItems: 0, oldestOrderAt: nil,                        zone: bar),
            TableItem(id: 7, name: "Terrasse 1", isActive: true, openOrdersCount: 1, totalOpenCents: 1200,  totalOpenItems: 1, oldestOrderAt: "2026-03-17T08:55:00.000Z", zone: nil),
        ]
        return store
    }

    static var previewEmpty: TableStore { TableStore() }
}

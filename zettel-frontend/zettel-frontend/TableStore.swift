// TableStore.swift
// cashbox — Tischliste + Zonen laden

import Foundation

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
            tables = try await api.get("/tables")
            // Zonen aus den Tischen ableiten (sortiert, dedupliziert)
            var seen = Set<Int>()
            zones = tables
                .compactMap { $0.zone }
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: TableStore {
        let store = TableStore()
        let innen = TableZone(id: 1, name: "Innen", sortOrder: 0)
        let bar   = TableZone(id: 2, name: "Bar",   sortOrder: 1)
        store.zones = [innen, bar]
        store.tables = [
            TableItem(id: 1, name: "Tisch 1",    isActive: true, openOrdersCount: 2, zone: innen),
            TableItem(id: 2, name: "Tisch 2",    isActive: true, openOrdersCount: 0, zone: innen),
            TableItem(id: 3, name: "Tisch 3",    isActive: true, openOrdersCount: 1, zone: innen),
            TableItem(id: 4, name: "Tisch 4",    isActive: true, openOrdersCount: 0, zone: innen),
            TableItem(id: 5, name: "Bar 1",      isActive: true, openOrdersCount: 3, zone: bar),
            TableItem(id: 6, name: "Bar 2",      isActive: true, openOrdersCount: 0, zone: bar),
            TableItem(id: 7, name: "Terrasse 1", isActive: true, openOrdersCount: 0, zone: nil),
        ]
        return store
    }

    static var previewEmpty: TableStore { TableStore() }
}

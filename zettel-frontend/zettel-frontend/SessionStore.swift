// SessionStore.swift
// cashbox — Kassensitzung: öffnen, schließen, Movements

import Foundation

@MainActor
final class SessionStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var currentSession: CashRegisterSession?
    @Published private(set) var lastZReport:    CloseSessionResult?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Computed ───────────────────────────────────────────────────────────
    var hasOpenSession: Bool { currentSession != nil }

    // ── Public Interface ───────────────────────────────────────────────────

    /// Lädt die aktuelle offene Session dieses Geräts.
    /// 404 = keine Session offen — kein Fehler, nur currentSession = nil.
    func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentSession = try await api.get("/sessions/current")
        } catch AppError.serverError(404, _) {
            currentSession = nil
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Öffnet eine neue Kassensitzung.
    func open(openingCashCents: Int) async throws {
        isLoading = true
        defer { isLoading = false }
        let body = OpenSessionBody(openingCashCents: openingCashCents)
        let _: OpenSessionResponse = try await api.post("/sessions/open", body: body)
        await loadCurrent()
    }

    /// Schließt die aktuelle Session und gibt das Z-Bericht-Ergebnis zurück.
    func close(closingCashCents: Int) async throws -> CloseSessionResult {
        isLoading = true
        defer { isLoading = false }
        let body = CloseSessionBody(closingCashCents: closingCashCents)
        let result: CloseSessionResult = try await api.post("/sessions/close", body: body)
        currentSession = nil
        lastZReport = result
        return result
    }

    /// Lädt den Z-Bericht einer abgeschlossenen Session.
    func loadZReport(sessionId: Int) async throws {
        isLoading = true
        defer { isLoading = false }
        lastZReport = try await api.get("/sessions/\(sessionId)/z-report")
    }

    /// Fügt eine Einlage oder Entnahme zur aktuellen Session hinzu.
    func addMovement(type: MovementType, amountCents: Int, reason: String) async throws {
        guard let session = currentSession else {
            throw AppError.noActiveSession
        }
        let body = AddMovementBody(type: type, amountCents: amountCents, reason: reason)
        let _: EmptyResponse = try await api.post("/sessions/\(session.id)/movements", body: body)
        await loadCurrent()
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: SessionStore {
        let store = SessionStore()
        store.currentSession = CashRegisterSession(
            id: 1,
            status: "open",
            openingCashCents: 15000,
            openedAt: "2026-03-16T08:00:00.000Z",
            openedByName: "Niko",
            movements: []
        )
        return store
    }

    static var previewNoSession: SessionStore {
        SessionStore()
    }

    static var previewWithZReport: SessionStore {
        let store = SessionStore()
        store.lastZReport = CloseSessionResult(
            sessionId: 1, zReportId: 12,
            closingCashCents: 37000, expectedCashCents: 37000,
            differenceCents: 0,
            totalRevenueCents: 48750, totalOrders: 12,
            totalDiscountCents: 500, cancellationCount: 1
        )
        return store
    }
}

// MARK: - Request Bodies (privat)

private struct OpenSessionBody: Encodable {
    let openingCashCents: Int
}

private struct OpenSessionResponse: Decodable {
    let id: Int
    let status: String
    let openingCashCents: Int
}

private struct CloseSessionBody: Encodable {
    let closingCashCents: Int
}

private struct AddMovementBody: Encodable {
    let type: MovementType
    let amountCents: Int
    let reason: String
}

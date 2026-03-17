// ReportStore.swift
// cashbox — Tagesberichte und Zusammenfassungen: GET /reports/daily + /reports/summary

import Foundation

@MainActor
final class ReportStore: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var dailyReport:   DailyReport?
    @Published private(set) var summaryReport: SummaryReport?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    func loadDaily(date: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }
        let dateStr = isoDate(date)
        do {
            dailyReport = try await api.get("/reports/daily?date=\(dateStr)")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func loadSummary(from: Date, to: Date) async {
        isLoading = true
        defer { isLoading = false }
        let fromStr = isoDate(from)
        let toStr   = isoDate(to)
        do {
            summaryReport = try await api.get("/reports/summary?from=\(fromStr)&to=\(toStr)")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func clearError() { error = nil }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: ReportStore {
        let store = ReportStore()
        store.dailyReport = DailyReport(
            date: "2026-03-17",
            receiptCount: 12,
            cancellationCount: 1,
            totalGrossCents: 48750,
            vat7NetCents: 2804,
            vat7TaxCents: 196,
            vat19NetCents: 38613,
            vat19TaxCents: 7137,
            paymentsCashCents: 22000,
            paymentsCardCents: 26750,
            sessions: [
                ReportSession(
                    id: 1, openedAt: "2026-03-17T10:00:00.000Z",
                    closedAt: "2026-03-17T22:00:00.000Z",
                    openingCashCents: 15000, closingCashCents: 37000,
                    expectedCashCents: 37000, differenceCents: 0,
                    status: "closed"
                )
            ]
        )
        store.summaryReport = SummaryReport(
            from: "2026-03-11", to: "2026-03-17",
            receiptCount: 74,
            totalGrossCents: 312400,
            vat7NetCents: 18000,
            vat7TaxCents: 1260,
            vat19NetCents: 246756,
            vat19TaxCents: 46884,
            paymentsCashCents: 145000,
            paymentsCardCents: 167400,
            byDay: [
                DaySummary(date: "2026-03-11", receiptCount: 9,  totalGrossCents: 38200, paymentsCashCents: 18000, paymentsCardCents: 20200),
                DaySummary(date: "2026-03-12", receiptCount: 11, totalGrossCents: 44700, paymentsCashCents: 21000, paymentsCardCents: 23700),
                DaySummary(date: "2026-03-13", receiptCount: 8,  totalGrossCents: 32100, paymentsCashCents: 15000, paymentsCardCents: 17100),
                DaySummary(date: "2026-03-14", receiptCount: 14, totalGrossCents: 58900, paymentsCashCents: 28000, paymentsCardCents: 30900),
                DaySummary(date: "2026-03-15", receiptCount: 13, totalGrossCents: 55100, paymentsCashCents: 26000, paymentsCardCents: 29100),
                DaySummary(date: "2026-03-16", receiptCount: 7,  totalGrossCents: 34650, paymentsCashCents: 17000, paymentsCardCents: 17650),
                DaySummary(date: "2026-03-17", receiptCount: 12, totalGrossCents: 48750, paymentsCashCents: 20000, paymentsCardCents: 28750),
            ]
        )
        return store
    }

    static var previewEmpty: ReportStore { ReportStore() }
}

// MARK: - Helpers

private func isoDate(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt.string(from: date)
}

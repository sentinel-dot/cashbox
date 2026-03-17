// ZBerichtView.swift
// cashbox — Z-Bericht: letzter Schichtabschluss, Umsatz, Zähler, Kassendifferenz

import SwiftUI

// MARK: - Root

struct ZBerichtView: View {
    @EnvironmentObject var sessionStore:   SessionStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @State private var error:     AppError?
    @State private var showError  = false

    private var report: CloseSessionResult? { sessionStore.lastZReport }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZTopBar()

                if sessionStore.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if let r = report {
                    ZBerichtContent(report: r)
                } else {
                    EmptyZBericht()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }
}

// MARK: - Top Bar

private struct ZTopBar: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Z-Bericht")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Letzter Schichtabschluss")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

// MARK: - Kein Z-Bericht

private struct EmptyZBericht: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.C.text2)
            Text("Kein Z-Bericht vorhanden")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text("Schließe eine Kassensitzung ab um den Z-Bericht hier zu sehen.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Z-Bericht Content

private struct ZBerichtContent: View {
    let report: CloseSessionResult
    @Environment(\.colorScheme) private var colorScheme

    var differenzColor: Color {
        report.differenceCents == 0 ? DS.C.text : (report.differenceCents > 0 ? DS.C.acc : Color(hex: "e74c3c"))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header-Chip
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(DS.C.accBg).frame(width: 44, height: 44)
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Z-Bericht #\(report.zReportId)")
                            .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Text("Session #\(report.sessionId)")
                            .font(.jakarta(DS.T.loginFooter, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    Spacer()
                }
                .padding(16)
                .background(DS.C.sur)
                .cornerRadius(DS.R.card)
                .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))

                // Umsatz-Kacheln
                HStack(spacing: 12) {
                    ZKachel(
                        icon: "eurosign.circle.fill",
                        label: "Gesamtumsatz",
                        value: formatCents(report.totalRevenueCents),
                        accent: true
                    )
                    ZKachel(
                        icon: "doc.fill",
                        label: "Bons",
                        value: "\(report.totalOrders)"
                    )
                    ZKachel(
                        icon: "percent",
                        label: "Rabatte",
                        value: formatCents(report.totalDiscountCents)
                    )
                    ZKachel(
                        icon: "xmark.circle",
                        label: "Stornos",
                        value: "\(report.cancellationCount)"
                    )
                }

                // Kassenbestand
                ZSection("KASSENBESTAND") {
                    ZRow(label: "Eröffnungsbestand", value: formatCents(report.closingCashCents))
                    ZRow(label: "Ist-Bestand",        value: formatCents(report.closingCashCents))
                    ZRow(label: "Soll-Bestand",       value: formatCents(report.expectedCashCents))
                    Divider()
                    ZRow(
                        label: "Differenz",
                        value: (report.differenceCents >= 0 ? "+" : "") + formatCents(report.differenceCents),
                        valueColor: differenzColor,
                        bold: true
                    )
                }

                // MwSt — Platzhalter (CloseSessionResult hat keine VAT-Aufschlüsselung)
                ZSection("HINWEIS") {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(DS.C.text2)
                        Text("Detaillierte MwSt-Aufschlüsselung ist in den Tagesberichten verfügbar.")
                            .font(.jakarta(DS.T.loginBody, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                }
            }
            .padding(20)
        }
        .background(DS.C.bg)
    }
}

private struct ZKachel: View {
    let icon:   String
    let label:  String
    let value:  String
    var accent: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent ? DS.C.acc : DS.C.text2)
            Spacer()
            Text(value)
                .font(.jakarta(16, weight: .semibold))
                .foregroundColor(DS.C.text)
                .tracking(-0.2)
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

private struct ZSection<Content: View>: View {
    let title:   String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
            VStack(spacing: 6) { content }
                .padding(12)
                .background(DS.C.sur)
                .cornerRadius(DS.R.card)
                .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
        }
    }
}

private struct ZRow: View {
    let label:      String
    let value:      String
    var valueColor: Color? = nil
    var bold:       Bool   = false

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(DS.C.text)
            Spacer()
            Text(value)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(valueColor ?? DS.C.text)
        }
    }
}

// MARK: - Helpers

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
}

// MARK: - Previews


#Preview("Mit Z-Bericht") {
    ZBerichtView()
        .environmentObject(SessionStore.previewWithZReport)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Kein Z-Bericht") {
    ZBerichtView()
        .environmentObject(SessionStore.previewNoSession)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    ZBerichtView()
        .environmentObject(SessionStore.previewWithZReport)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

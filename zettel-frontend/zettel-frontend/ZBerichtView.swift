// ZBerichtView.swift
// cashbox — Z-Bericht: Schichtabschluss-Dokument nach Referenz-Design

import SwiftUI

// MARK: - Root

struct ZBerichtView: View {
    @EnvironmentObject var sessionStore:   SessionStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    private var report: CloseSessionResult? { sessionStore.lastZReport }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ZToolbar(report: report)
                if sessionStore.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular).scaleEffect(1.2)
                    Spacer()
                } else if let r = report {
                    ZTwoCol(report: r)
                } else {
                    ZEmptyState()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }
}

// MARK: - Toolbar

private struct ZToolbar: View {
    let report: CloseSessionResult?

    var body: some View {
        HStack(spacing: 12) {
            // Left: report label
            HStack(spacing: 8) {
                Text("Schicht:")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
                if let r = report {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(DS.C.text2)
                        Text("Z-Bericht #\(r.zReportId) · Session #\(r.sessionId)")
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(DS.C.bg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brdLight, lineWidth: 1)
                    )
                } else {
                    Text("Kein Z-Bericht")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }
            Spacer()
            // Right: action buttons (Phase 5)
            HStack(spacing: 8) {
                Button {
                    // PDF export — Phase 5
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("PDF exportieren")
                            .font(.jakarta(12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(DS.C.acc.opacity(report == nil ? 0.4 : 1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(report == nil)

                Button {
                    // DSFinV-K export — Phase 5
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                        Text("DSFinV-K")
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(DS.C.sur2)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brdLight, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(report == nil)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Two-Column Layout

private struct ZTwoCol: View {
    let report: CloseSessionResult

    var body: some View {
        HStack(spacing: 0) {
            // Left: Z-Bericht document
            ZDocumentPanel(report: report)
                .frame(maxWidth: .infinity)

            Rectangle().fill(DS.C.brdLight).frame(width: 1)

            // Right: session list (320px)
            ZSessionListPanel(report: report)
                .frame(width: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Document Panel (left)

private struct ZDocumentPanel: View {
    let report: CloseSessionResult

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack {
                Spacer(minLength: 0)
                ZDocument(report: report)
                    .frame(maxWidth: 520)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Z-Bericht Document

private struct ZDocument: View {
    let report: CloseSessionResult
    @Environment(\.colorScheme) private var colorScheme

    private var diffColor: Color {
        report.differenceCents == 0
            ? DS.C.successText
            : (report.differenceCents > 0 ? DS.C.acc : DS.C.dangerText)
    }

    private var diffLabel: String {
        if report.differenceCents == 0 { return "± " + zbFmt(0) }
        return (report.differenceCents > 0 ? "+ " : "− ") + zbFmt(abs(report.differenceCents))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZDocHeader(report: report)

            // Meta 2×2
            ZDocMeta(report: report)

            // Umsatz
            ZDocSection(title: "Umsatz") {
                ZDocRow(label: "Bruttoumsatz gesamt",  value: zbFmt(report.totalRevenueCents))
                if report.totalDiscountCents > 0 {
                    ZDocRow(label: "Rabatte", value: "− " + zbFmt(report.totalDiscountCents),
                            valueColor: DS.C.dangerText)
                }
                if report.cancellationCount > 0 {
                    ZDocRow(label: "Stornos (\(report.cancellationCount)×)",
                            value: "−",
                            valueColor: DS.C.dangerText)
                }
                ZDocDivider()
                ZDocTotalRow(label: "Nettoumsatz gesamt", value: zbFmt(report.totalRevenueCents))
            }

            // Kassenstand
            ZDocSection(title: "Kassenstand") {
                ZDocRow(label: "Ist-Bestand (gezählt)",  value: zbFmt(report.closingCashCents))
                ZDocRow(label: "Soll-Bestand (erwartet)", value: zbFmt(report.expectedCashCents))
                ZDocDivider()
                ZDocRow(label: "Differenz", value: diffLabel,
                        valueColor: diffColor, bold: true)
                    .padding(.bottom, 4)
            }

            // Transaktionen
            ZDocSection(title: "Transaktionen") {
                ZDocRow(label: "Bons gesamt",  value: "\(report.totalOrders)")
                ZDocRow(label: "Stornobons",   value: "\(report.cancellationCount)")
                ZDocRow(label: "Z-Bericht Nr", value: "#\(report.zReportId)")
                ZDocRow(label: "Session Nr",   value: "#\(report.sessionId)")
                    .padding(.bottom, 4)
            }

            // TSE (Phase 1 placeholder)
            ZDocTSESection()

            // Footer
            ZDocFooter()
        }
        .background(DS.C.sur)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Document Subcomponents

private struct ZDocHeader: View {
    let report: CloseSessionResult

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kassensystem")
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Z-Bericht #\(report.zReportId) · Session #\(report.sessionId)")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .lineSpacing(2)
            }
            Spacer()
            Text("Z-Bericht")
                .font(.jakarta(10, weight: .semibold))
                .foregroundColor(DS.C.accT)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(DS.C.accBg)
                .cornerRadius(6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZDocMeta: View {
    let report: CloseSessionResult

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 0
        ) {
            ZDocMetaCell(label: "Z-Bericht Nr",  value: "#\(report.zReportId)",   rightBorder: true, bottomBorder: true)
            ZDocMetaCell(label: "Session Nr",    value: "#\(report.sessionId)",   rightBorder: false, bottomBorder: true)
            ZDocMetaCell(label: "Bons gesamt",   value: "\(report.totalOrders)",  rightBorder: true, bottomBorder: false)
            ZDocMetaCell(label: "Stornos",       value: "\(report.cancellationCount)", rightBorder: false, bottomBorder: false)
        }
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZDocMetaCell: View {
    let label:        String
    let value:        String
    let rightBorder:  Bool
    let bottomBorder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
            Text(value)
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .frame(width: rightBorder ? 1 : 0)
                .foregroundColor(DS.C.brdLight),
            alignment: .trailing
        )
        .overlay(
            Rectangle()
                .frame(height: bottomBorder ? 1 : 0)
                .foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZDocSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.6)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 6)
            content
        }
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZDocRow: View {
    let label:      String
    let value:      String
    var valueColor: Color? = nil
    var bold:       Bool   = false

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(12, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.text : DS.C.text2)
            Spacer()
            Text(value)
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(valueColor ?? DS.C.text)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
    }
}

private struct ZDocTotalRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(DS.C.text)
            Spacer()
            Text(value)
                .font(.jakarta(16, weight: .semibold))
                .foregroundColor(DS.C.acc)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(DS.C.bg)
    }
}

private struct ZDocDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.C.brdLight)
            .frame(height: 1)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
    }
}

private struct ZDocTSESection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TSE-Signatur (Fiskaly)")
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.6)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(DS.C.text2)
                Text("TSE-Aktivierung ausstehend — Signatur nach Fiskaly-Inbetriebnahme verfügbar.")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.C.bg)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZDocFooter: View {
    var body: some View {
        HStack(alignment: .top) {
            Text("Dieser Z-Bericht ist unveränderlich (GoBD).\nAufbewahrungspflicht: 10 Jahre.")
                .font(.jakarta(10, weight: .regular))
                .foregroundColor(DS.C.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("READ ONLY")
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.3)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.C.sur2)
                .cornerRadius(4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Session List Panel (right)

private struct ZSessionListPanel: View {
    let report: CloseSessionResult
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Alle Z-Berichte")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Unveränderlich · GoBD-konform")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
                alignment: .bottom
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Month label
                    Text("Aktuelle Sitzung")
                        .font(.jakarta(9, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    // Selected item
                    ZSlpItem(
                        report:   report,
                        isActive: true
                    )

                    // History hint
                    VStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(DS.C.text2)
                        Text("Ältere Z-Berichte")
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Text("Über den Berichte-Screen\nabrufbar.")
                            .font(.jakarta(11, weight: .regular))
                            .foregroundColor(DS.C.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(DS.C.bg)
    }
}

private struct ZSlpItem: View {
    let report:   CloseSessionResult
    let isActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? DS.C.accBg : DS.C.sur2)
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isActive ? DS.C.accT : DS.C.text2)
            }

            // Info
            VStack(alignment: .leading, spacing: 1) {
                Text("Z-Bericht #\(report.zReportId)")
                    .font(.jakarta(12, weight: .medium))
                    .foregroundColor(DS.C.text)
                Text("Session #\(report.sessionId) · \(report.totalOrders) Bons")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Amount + diff
            VStack(alignment: .trailing, spacing: 1) {
                Text(zbFmt(report.totalRevenueCents))
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                let diffText = report.differenceCents == 0
                    ? "± 0,00 €"
                    : (report.differenceCents > 0 ? "+ " : "− ") + zbFmt(abs(report.differenceCents))
                Text(diffText)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(
                        report.differenceCents == 0
                            ? DS.C.successText
                            : DS.C.warnText
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isActive ? DS.C.sur : Color.clear)
        .overlay(
            Rectangle()
                .frame(width: isActive ? 3 : 0)
                .foregroundColor(DS.C.acc),
            alignment: .leading
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Empty State

private struct ZEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(DS.C.text2)
            Text("Kein Z-Bericht vorhanden")
                .font(.jakarta(18, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text("Schließe eine Kassensitzung ab\num den Z-Bericht hier zu sehen.")
                .font(.jakarta(14, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

private func zbFmt(_ cents: Int) -> String {
    let fmt = NumberFormatter()
    fmt.locale                = Locale(identifier: "de_DE")
    fmt.numberStyle           = .decimal
    fmt.minimumFractionDigits = 2
    fmt.maximumFractionDigits = 2
    return (fmt.string(from: NSNumber(value: Double(cents) / 100)) ?? "0,00") + " €"
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

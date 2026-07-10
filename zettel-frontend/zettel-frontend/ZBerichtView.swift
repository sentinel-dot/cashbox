// ZBerichtView.swift
// cashbox — Z-Bericht: Schichtabschluss-Dokument
// Design v3: Dokument mit Beleg-Charakter (Monospace-Ziffern), keine
// Seitenstreifen, zentrale Geld-Formatierung.

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
                    DSEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "Kein Z-Bericht vorhanden",
                        message: "Schließe eine Kassensitzung ab, um den Z-Bericht hier zu sehen."
                    )
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
    }
}

// MARK: - Toolbar

private struct ZToolbar: View {
    let report: CloseSessionResult?

    var body: some View {
        HStack(spacing: 12) {
            if let r = report {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.C.text2)
                    Text("Z-Bericht #\(r.zReportId) · Session #\(r.sessionId)")
                        .font(DS.F.subBold)
                        .monospacedDigit()
                        .foregroundColor(DS.C.text)
                }
            } else {
                Text("Kein Z-Bericht")
                    .font(DS.F.sub)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            // Aktionen (Phase 5)
            HStack(spacing: 8) {
                Button {
                    // PDF export — Phase 5
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc")
                            .font(.system(size: 13, weight: .semibold))
                        Text("PDF exportieren")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 42, fullWidth: false))
                .disabled(report == nil)

                Button {
                    // DSFinV-K export — Phase 5
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 13, weight: .semibold))
                        Text("DSFinV-K")
                    }
                }
                .buttonStyle(DSSecondaryButton(height: 42, fullWidth: false))
                .disabled(report == nil)
            }
        }
        .padding(.horizontal, DS.S.pagePad)
        .frame(height: DS.S.topbarHeight + 8)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

// MARK: - Two-Column Layout

private struct ZTwoCol: View {
    let report: CloseSessionResult

    var body: some View {
        HStack(spacing: 0) {
            ZDocumentPanel(report: report)
                .frame(maxWidth: .infinity)

            Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)

            ZSessionListPanel(report: report)
                .frame(width: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Document Panel (links)

private struct ZDocumentPanel: View {
    let report: CloseSessionResult

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack {
                Spacer(minLength: 0)
                ZDocument(report: report)
                    .frame(maxWidth: 540)
                Spacer(minLength: 0)
            }
            .padding(DS.S.pagePad)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Z-Bericht Document

private struct ZDocument: View {
    let report: CloseSessionResult

    private var diffColor: Color {
        report.differenceCents == 0
            ? DS.C.successText
            : (report.differenceCents > 0 ? DS.C.accT : DS.C.dangerText)
    }

    private var diffLabel: String {
        if report.differenceCents == 0 { return "± " + euroString(0) }
        return (report.differenceCents > 0 ? "+ " : "− ") + euroString(abs(report.differenceCents))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZDocHeader(report: report)
            ZDocMeta(report: report)

            // Umsatz
            ZDocSection(title: "Umsatz") {
                ZDocRow(label: "Bruttoumsatz gesamt",  value: euroString(report.totalRevenueCents))
                if report.totalDiscountCents > 0 {
                    ZDocRow(label: "Rabatte", value: "− " + euroString(report.totalDiscountCents),
                            valueColor: DS.C.dangerText)
                }
                if report.cancellationCount > 0 {
                    ZDocRow(label: "Stornos (\(report.cancellationCount)×)",
                            value: "−",
                            valueColor: DS.C.dangerText)
                }
                ZDocDivider()
                ZDocTotalRow(label: "Umsatz gesamt", value: euroString(report.totalRevenueCents))
            }

            // Kassenstand
            ZDocSection(title: "Kassenstand") {
                ZDocRow(label: "Ist-Bestand (gezählt)",  value: euroString(report.closingCashCents))
                ZDocRow(label: "Soll-Bestand (erwartet)", value: euroString(report.expectedCashCents))
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

            ZDocFooter()
        }
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
        )
    }
}

// MARK: - Document Subcomponents

private struct ZDocHeader: View {
    let report: CloseSessionResult

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("cashbox")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(DS.C.text)
                Text("Z-Bericht #\(report.zReportId) · Session #\(report.sessionId)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            DSPill(label: "Z-Bericht", fg: DS.C.accT, bg: DS.C.accBg, showDot: false)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
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
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
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
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.C.text2)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.C.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .overlay(
            Rectangle()
                .frame(width: rightBorder ? 1 : 0)
                .foregroundColor(DS.C.brdAdaptive),
            alignment: .trailing
        )
        .overlay(
            Rectangle()
                .frame(height: bottomBorder ? 1 : 0)
                .foregroundColor(DS.C.brdAdaptive),
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
            DSSectionLabel(text: title)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)
            content
        }
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
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
                .font(.system(size: 14, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.text : DS.C.text2)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor ?? DS.C.text)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }
}

private struct ZDocTotalRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.C.text)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(DS.C.accT)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(DS.C.sur2.opacity(0.5))
    }
}

private struct ZDocDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.C.brdAdaptive)
            .frame(height: 1)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
    }
}

private struct ZDocTSESection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSSectionLabel(text: "TSE-Signatur (Fiskaly)")
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundColor(DS.C.brassText)
                Text("TSE-Aktivierung ausstehend — Signatur nach Fiskaly-Inbetriebnahme verfügbar.")
                    .font(DS.F.caption)
                    .foregroundColor(DS.C.brassText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.C.brassBg.opacity(0.5))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

private struct ZDocFooter: View {
    var body: some View {
        HStack(alignment: .center) {
            Text("Dieser Z-Bericht ist unveränderlich (GoBD). Aufbewahrungspflicht: 10 Jahre.")
                .font(DS.F.caption)
                .foregroundColor(DS.C.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .semibold))
                Text("Unveränderlich")
                    .font(DS.F.label)
            }
            .foregroundColor(DS.C.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(DS.C.sur2))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Session List Panel (rechts)

private struct ZSessionListPanel: View {
    let report: CloseSessionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alle Z-Berichte")
                    .font(DS.F.bodyBold)
                    .foregroundColor(DS.C.text)
                Text("Unveränderlich · GoBD-konform")
                    .font(DS.F.caption)
                    .foregroundColor(DS.C.text2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
                alignment: .bottom
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    DSSectionLabel(text: "Aktuelle Sitzung")
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    ZSlpItem(report: report, isActive: true)
                        .padding(.horizontal, 12)

                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(DS.C.text2)
                        Text("Ältere Z-Berichte")
                            .font(DS.F.subBold)
                            .foregroundColor(DS.C.text)
                        Text("Über den Berichte-Screen abrufbar.")
                            .font(DS.F.caption)
                            .foregroundColor(DS.C.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? DS.C.accBg : DS.C.sur2)
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? DS.C.accT : DS.C.text2)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Z-Bericht #\(report.zReportId)")
                    .font(DS.F.subBold)
                    .monospacedDigit()
                    .foregroundColor(DS.C.text)
                Text("Session #\(report.sessionId) · \(report.totalOrders) Bons")
                    .font(DS.F.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Text(euroString(report.totalRevenueCents))
                    .font(DS.F.money(14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(DS.C.text)
                let diffText = report.differenceCents == 0
                    ? "± 0,00 €"
                    : (report.differenceCents > 0 ? "+ " : "− ") + euroString(abs(report.differenceCents))
                Text(diffText)
                    .font(DS.F.caption)
                    .monospacedDigit()
                    .foregroundColor(
                        report.differenceCents == 0
                            ? DS.C.successText
                            : DS.C.brassText
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.R.input)
                .fill(isActive ? DS.C.sur : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.input)
                .strokeBorder(isActive ? DS.C.brdAdaptive : Color.clear, lineWidth: 1)
        )
    }
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

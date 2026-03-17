// BerichteView.swift
// cashbox — Tagesberichte und Wochenübersicht: Umsatz, MwSt, Bar/Karte-Aufteilung

import SwiftUI

// MARK: - Root

struct BerichteView: View {
    @EnvironmentObject var reportStore:   ReportStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    enum Tab { case taeglich, zusammenfassung }
    @State private var activeTab    = Tab.taeglich
    @State private var selectedDate = Date()
    @State private var summaryFrom  = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var summaryTo    = Date()

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                BerichteTopBar(activeTab: $activeTab)

                if activeTab == .taeglich {
                    TaeglichTab(selectedDate: $selectedDate)
                        .task(id: selectedDate) { await reportStore.loadDaily(date: selectedDate) }
                } else {
                    ZusammenfassungTab(from: $summaryFrom, to: $summaryTo)
                        .task(id: summaryFrom) {
                            await reportStore.loadSummary(from: summaryFrom, to: summaryTo)
                        }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }
}

// MARK: - Top Bar

private struct BerichteTopBar: View {
    @Binding var activeTab: BerichteView.Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Berichte")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }
            Spacer()
            // Tab-Switcher
            HStack(spacing: 0) {
                TabPill(label: "Täglich",    isActive: activeTab == .taeglich)    { activeTab = .taeglich }
                TabPill(label: "Zeitraum",   isActive: activeTab == .zusammenfassung) { activeTab = .zusammenfassung }
            }
            .background(DS.C.sur2)
            .cornerRadius(DS.R.button)
        }
        .padding(.horizontal, 24)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct TabPill: View {
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text2)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(isActive ? DS.C.acc : Color.clear)
                .cornerRadius(DS.R.button - 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Täglich-Tab

private struct TaeglichTab: View {
    @Binding var selectedDate: Date
    @EnvironmentObject var reportStore: ReportStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Links: Datumspicker + Bericht
            VStack(spacing: 0) {
                // Datum-Navigation
                HStack(spacing: 12) {
                    Button {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                    }
                    .buttonStyle(.plain)

                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Button {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                        if tomorrow <= Date() { selectedDate = tomorrow }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                    }
                    .buttonStyle(.plain)
                    .opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1)
                    .disabled(Calendar.current.isDateInToday(selectedDate))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(DS.C.sur)
                .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

                if reportStore.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if let r = reportStore.dailyReport {
                    DailyReportContent(report: r)
                } else {
                    EmptyBericht(message: "Für diesen Tag liegen keine Daten vor.")
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(DS.C.brdLight).frame(width: 1)

            // Rechts: Session-Liste
            SessionListPanel()
                .frame(width: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DailyReportContent: View {
    let report: DailyReport

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // KPI-Kacheln
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                    spacing: 12
                ) {
                    ReportKachel(icon: "eurosign.circle.fill", label: "Umsatz (Brutto)",    value: formatCents(report.totalGrossCents), accent: true)
                    ReportKachel(icon: "doc.fill",             label: "Bons",               value: "\(report.receiptCount)")
                    ReportKachel(icon: "banknote",             label: "Bar",                value: formatCents(report.paymentsCashCents))
                    ReportKachel(icon: "creditcard",           label: "Karte",              value: formatCents(report.paymentsCardCents))
                }

                if report.cancellationCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(Color(hex: "e74c3c"))
                        Text("\(report.cancellationCount) Stornierung\(report.cancellationCount == 1 ? "" : "en") an diesem Tag")
                            .font(.jakarta(DS.T.loginBody, weight: .regular))
                            .foregroundColor(DS.C.text2)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(hex: "e74c3c").opacity(0.08))
                    .cornerRadius(DS.R.card)
                }

                // MwSt
                ReportSection("MWST-AUFSCHLÜSSELUNG") {
                    if report.vat7NetCents + report.vat7TaxCents > 0 {
                        ReportRow(label: "7 % Netto",  value: formatCents(report.vat7NetCents))
                        ReportRow(label: "7 % Steuer", value: formatCents(report.vat7TaxCents), dim: true)
                    }
                    if report.vat19NetCents + report.vat19TaxCents > 0 {
                        ReportRow(label: "19 % Netto",  value: formatCents(report.vat19NetCents))
                        ReportRow(label: "19 % Steuer", value: formatCents(report.vat19TaxCents), dim: true)
                    }
                    Divider()
                    ReportRow(label: "Gesamt (Brutto)", value: formatCents(report.totalGrossCents), bold: true)
                }
            }
            .padding(20)
        }
    }
}

private struct SessionListPanel: View {
    @EnvironmentObject var reportStore: ReportStore
    @Environment(\.colorScheme) private var colorScheme

    var sessions: [ReportSession] { reportStore.dailyReport?.sessions ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KASSENSITZUNGEN")
                .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(DS.C.sur)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            if sessions.isEmpty {
                Spacer()
                Text("Keine Sitzungen")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            SessionCard(session: session)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(DS.C.bg)
    }
}

private struct SessionCard: View {
    let session: ReportSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Session #\(session.id)")
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Text(session.status == "closed" ? "Geschlossen" : "Offen")
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(session.status == "closed" ? DS.C.text2 : DS.C.acc)
            }
            if let diff = session.differenceCents {
                HStack {
                    Text("Differenz")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text((diff >= 0 ? "+" : "") + formatCents(diff))
                        .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                        .foregroundColor(diff == 0 ? DS.C.acc : Color(hex: "e74c3c"))
                }
            }
        }
        .padding(10)
        .background(DS.C.sur)
        .cornerRadius(DS.R.pinRow)
        .overlay(RoundedRectangle(cornerRadius: DS.R.pinRow).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - Zusammenfassung-Tab

private struct ZusammenfassungTab: View {
    @Binding var from: Date
    @Binding var to:   Date
    @EnvironmentObject var reportStore: ReportStore

    var body: some View {
        VStack(spacing: 0) {
            // Zeitraum-Wähler
            HStack(spacing: 16) {
                Label("Von", systemImage: "calendar")
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                DatePicker("", selection: $from, in: ...to, displayedComponents: .date)
                    .labelsHidden()
                Text("bis")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
                DatePicker("", selection: $to, in: from...Date(), displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                // Schnellauswahl
                QuickRangeButton(label: "7 Tage")  { setRange(days: 6) }
                QuickRangeButton(label: "30 Tage") { setRange(days: 29) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            if reportStore.isLoading {
                Spacer(); ProgressView().progressViewStyle(.circular); Spacer()
            } else if let r = reportStore.summaryReport {
                SummaryContent(report: r)
            } else {
                EmptyBericht(message: "Wähle einen Zeitraum um Daten zu laden.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setRange(days: Int) {
        to   = Date()
        from = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}

private struct QuickRangeButton: View {
    let label: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(DS.C.acc)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.C.accBg)
                .cornerRadius(DS.R.button)
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryContent: View {
    let report: SummaryReport

    var body: some View {
        HStack(spacing: 0) {
            // Links: Balkendiagramm
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // KPIs
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                        spacing: 12
                    ) {
                        ReportKachel(icon: "eurosign.circle.fill", label: "Gesamtumsatz",   value: formatCents(report.totalGrossCents), accent: true)
                        ReportKachel(icon: "doc.fill",             label: "Bons gesamt",    value: "\(report.receiptCount)")
                        ReportKachel(icon: "banknote",             label: "Bar gesamt",     value: formatCents(report.paymentsCashCents))
                        ReportKachel(icon: "creditcard",           label: "Karte gesamt",   value: formatCents(report.paymentsCardCents))
                    }
                    // Tagesübersicht
                    ReportSection("NACH TAG") {
                        ForEach(report.byDay, id: \.date) { day in
                            HStack {
                                Text(formatShortDate(day.date))
                                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                                    .foregroundColor(DS.C.text)
                                    .frame(width: 80, alignment: .leading)
                                Text("\(day.receiptCount) Bons")
                                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                    .foregroundColor(DS.C.text2)
                                Spacer()
                                Text(formatCents(day.totalGrossCents))
                                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                                    .foregroundColor(DS.C.text)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(DS.C.brdLight).frame(width: 1)

            // Rechts: MwSt
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ReportSection("MWST-AUFSCHLÜSSELUNG") {
                        if report.vat7NetCents + report.vat7TaxCents > 0 {
                            ReportRow(label: "7 % Netto",  value: formatCents(report.vat7NetCents))
                            ReportRow(label: "7 % Steuer", value: formatCents(report.vat7TaxCents), dim: true)
                        }
                        if report.vat19NetCents + report.vat19TaxCents > 0 {
                            ReportRow(label: "19 % Netto",  value: formatCents(report.vat19NetCents))
                            ReportRow(label: "19 % Steuer", value: formatCents(report.vat19TaxCents), dim: true)
                        }
                        Divider()
                        ReportRow(label: "Gesamt", value: formatCents(report.totalGrossCents), bold: true)
                    }
                }
                .padding(20)
            }
            .frame(width: 280)
        }
    }
}

// MARK: - Shared Komponenten

private struct EmptyBericht: View {
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DS.C.text2)
            Text(message)
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReportKachel: View {
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
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(14)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

private struct ReportSection<Content: View>: View {
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

private struct ReportRow: View {
    let label: String
    let value: String
    var dim:   Bool = false
    var bold:  Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
            Spacer()
            Text(value)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.acc : (dim ? DS.C.text2 : DS.C.text))
        }
    }
}

// MARK: - Helpers

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
}

private func formatShortDate(_ iso: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "de_DE")
    guard let d = f.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "EE dd.MM."
    out.locale = Locale(identifier: "de_DE")
    return out.string(from: d)
}

// MARK: - Previews

#Preview("Täglich") {
    BerichteView()
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    BerichteView()
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

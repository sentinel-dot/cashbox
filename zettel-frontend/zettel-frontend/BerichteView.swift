// BerichteView.swift
// cashbox — Berichte: Umsatz, Zahlungsarten, MwSt nach Referenz-Design

import SwiftUI

// MARK: - Range

fileprivate enum BRange: String, CaseIterable {
    case heute    = "Heute"
    case sieben   = "7 Tage"
    case dreissig = "30 Tage"
    case monat    = "Monat"
    case custom   = "Benutzerdefiniert"
}

// MARK: - Root

struct BerichteView: View {
    @EnvironmentObject var reportStore:    ReportStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var range      = BRange.heute
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customTo   = Date()

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                BToolbar(range: $range, customFrom: $customFrom, customTo: $customTo)
                if reportStore.isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular).scaleEffect(1.2)
                    Spacer()
                } else {
                    BContent(range: range)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .task(id: range)      { await loadData() }
        .task(id: customFrom) { if range == .custom { await loadData() } }
        .task(id: customTo)   { if range == .custom { await loadData() } }
    }

    private func loadData() async {
        let cal   = Calendar.current
        let today = Date()
        switch range {
        case .heute:
            await reportStore.loadDaily(date: today)
        case .sieben:
            await reportStore.loadSummary(
                from: cal.date(byAdding: .day, value: -6, to: today) ?? today,
                to: today
            )
        case .dreissig:
            await reportStore.loadSummary(
                from: cal.date(byAdding: .day, value: -29, to: today) ?? today,
                to: today
            )
        case .monat:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            await reportStore.loadSummary(from: start, to: today)
        case .custom:
            await reportStore.loadSummary(from: customFrom, to: customTo)
        }
    }
}

// MARK: - Toolbar

private struct BToolbar: View {
    @Binding var range:      BRange
    @Binding var customFrom: Date
    @Binding var customTo:   Date

    var body: some View {
        HStack(spacing: 6) {
            // Range pills
            ForEach(BRange.allCases, id: \.self) { r in
                RangePill(label: r.rawValue, isActive: range == r) {
                    withAnimation(.easeInOut(duration: 0.15)) { range = r }
                }
            }
            Spacer()
            // Date display / custom pickers
            if range == .custom {
                HStack(spacing: 6) {
                    DatePicker("", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Text("–")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    DatePicker("", selection: $customTo, in: customFrom...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .transition(.opacity)
            } else {
                Text(toolbarDateLabel)
                    .font(.jakarta(12, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(DS.C.bg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brdLight, lineWidth: 1)
                    )
            }
            // Export button (Phase 5)
            Button {
                // DSFinV-K export — Phase 5
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                    Text("Exportieren")
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
        }
        .padding(.horizontal, 20)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }

    private var toolbarDateLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "dd.MM.yyyy"
        let today = Date()
        let cal   = Calendar.current
        switch range {
        case .heute:
            return fmt.string(from: today)
        case .sieben:
            let from = cal.date(byAdding: .day, value: -6, to: today) ?? today
            return "\(fmt.string(from: from)) – \(fmt.string(from: today))"
        case .dreissig:
            let from = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return "\(fmt.string(from: from)) – \(fmt.string(from: today))"
        case .monat:
            let f2 = DateFormatter()
            f2.locale = Locale(identifier: "de_DE")
            f2.dateFormat = "MMMM yyyy"
            return f2.string(from: today)
        case .custom:
            return ""
        }
    }
}

private struct RangePill: View {
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(11, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text2)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(isActive ? DS.C.acc : Color.clear)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isActive ? DS.C.acc : DS.C.brdLight, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Main Content

private struct BContent: View {
    let range: BRange
    @EnvironmentObject var reportStore: ReportStore

    // Unified KPI sources
    private var totalGross: Int { reportStore.dailyReport?.totalGrossCents   ?? reportStore.summaryReport?.totalGrossCents   ?? 0 }
    private var receiptCnt: Int { reportStore.dailyReport?.receiptCount       ?? reportStore.summaryReport?.receiptCount       ?? 0 }
    private var cancelCnt:  Int { reportStore.dailyReport?.cancellationCount  ?? 0 }
    private var cashCents:  Int { reportStore.dailyReport?.paymentsCashCents  ?? reportStore.summaryReport?.paymentsCashCents  ?? 0 }
    private var cardCents:  Int { reportStore.dailyReport?.paymentsCardCents  ?? reportStore.summaryReport?.paymentsCardCents  ?? 0 }
    private var vat7Net:    Int { reportStore.dailyReport?.vat7NetCents       ?? reportStore.summaryReport?.vat7NetCents       ?? 0 }
    private var vat7Tax:    Int { reportStore.dailyReport?.vat7TaxCents       ?? reportStore.summaryReport?.vat7TaxCents       ?? 0 }
    private var vat19Net:   Int { reportStore.dailyReport?.vat19NetCents      ?? reportStore.summaryReport?.vat19NetCents      ?? 0 }
    private var vat19Tax:   Int { reportStore.dailyReport?.vat19TaxCents      ?? reportStore.summaryReport?.vat19TaxCents      ?? 0 }
    private var avgBon:     Int { receiptCnt > 0 ? totalGross / receiptCnt : 0 }
    private var vatTotal:   Int { vat7Tax + vat19Tax }
    private var days:       [DaySummary] { reportStore.summaryReport?.byDay ?? [] }
    private var hasData:    Bool { totalGross > 0 || receiptCnt > 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // 5 KPI cards
                BKPIRow(
                    totalGross: totalGross,
                    receiptCnt: receiptCnt,
                    avgBon:     avgBon,
                    cancelCnt:  cancelCnt,
                    vatTotal:   vatTotal
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Main 2-column grid
                HStack(alignment: .top, spacing: 16) {
                    // Left column
                    VStack(spacing: 16) {
                        if !hasData {
                            BReportEmpty()
                        } else if !days.isEmpty {
                            BarChartCard(days: Array(days.suffix(14)))
                            DayTableCard(days: days)
                        } else if let daily = reportStore.dailyReport {
                            TodayCard(report: daily)
                            if !daily.sessions.isEmpty {
                                BSessionsCard(sessions: daily.sessions)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right column (340px)
                    VStack(spacing: 16) {
                        ZahlungsartenCard(cashCents: cashCents, cardCents: cardCents)
                        MwStCard(
                            vat19Net: vat19Net, vat19Tax: vat19Tax,
                            vat7Net:  vat7Net,  vat7Tax:  vat7Tax,
                            vatTotal: vatTotal
                        )
                        if cancelCnt > 0 {
                            StornosCard(count: cancelCnt)
                        }
                    }
                    .frame(width: 340)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - KPI Row

private struct BKPIRow: View {
    let totalGross: Int
    let receiptCnt: Int
    let avgBon:     Int
    let cancelCnt:  Int
    let vatTotal:   Int

    var body: some View {
        HStack(spacing: 12) {
            BKPICard(label: "Umsatz (brutto)",  value: bFmtCents(totalGross), color: DS.C.acc,                                 delta: nil)
            BKPICard(label: "Transaktionen",    value: "\(receiptCnt)",        color: DS.C.text,                                delta: nil)
            BKPICard(label: "Ø Bon-Wert",       value: bFmtCents(avgBon),     color: DS.C.text,                                delta: nil)
            BKPICard(label: "Stornos",          value: "\(cancelCnt)",         color: cancelCnt > 0 ? DS.C.dangerText : DS.C.text, delta: nil)
            BKPICard(label: "MwSt gesamt",      value: bFmtCents(vatTotal),   color: DS.C.text,                                delta: "19 % + 7 %")
        }
    }
}

private struct BKPICard: View {
    let label: String
    let value: String
    let color: Color
    let delta: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.6)
                .lineLimit(1)
            Text(value)
                .font(.jakarta(19, weight: .semibold))
                .foregroundColor(color)
                .tracking(-0.3)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            if let d = delta {
                Text(d)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            } else {
                // Reserve space so all cards have same height
                Text(" ")
                    .font(.jakarta(10, weight: .regular))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.C.sur)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Bar Chart

private struct BarChartCard: View {
    let days: [DaySummary]
    @Environment(\.colorScheme) private var colorScheme
    private var maxVal: Int { days.map(\.totalGrossCents).max() ?? 1 }

    var body: some View {
        BSecCard {
            BSecHead(title: "Umsatz letzte 7 Tage", sub: "Tagesansicht")
            VStack(spacing: 0) {
                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                            let isToday = idx == days.count - 1
                            let frac    = maxVal > 0 ? CGFloat(day.totalGrossCents) / CGFloat(maxVal) : 0
                            BBarCol(day: day, frac: frac, isToday: isToday, maxH: geo.size.height)
                        }
                    }
                }
                .frame(height: 120)
                .padding(.bottom, 6)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(DS.C.brdLight),
                    alignment: .bottom
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }
}

private struct BBarCol: View {
    let day:     DaySummary
    let frac:    CGFloat
    let isToday: Bool
    let maxH:    CGFloat
    @State private var hovered = false

    private var label: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "de_DE")
        guard let d = f.date(from: day.date) else { return "" }
        if isToday { return "Heute" }
        let o = DateFormatter()
        o.dateFormat = "EEE"
        o.locale = Locale(identifier: "de_DE")
        return o.string(from: d)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.C.acc)
                .opacity(isToday ? 1.0 : (hovered ? 0.65 : 0.18))
                .frame(maxWidth: .infinity)
                .frame(height: max(4, frac * maxH))
                .animation(.easeOut(duration: 0.1), value: hovered)
            Text(bFmtShortCents(day.totalGrossCents))
                .font(.jakarta(9, weight: .semibold))
                .foregroundColor(isToday ? DS.C.acc : DS.C.text2)
                .lineLimit(1)
            Text(label)
                .font(.jakarta(9, weight: isToday ? .semibold : .regular))
                .foregroundColor(isToday ? DS.C.accT : DS.C.text2)
        }
        .frame(maxWidth: .infinity)
        .onHover { hovered = $0 }
    }
}

// MARK: - Day Table

private struct DayTableCard: View {
    let days: [DaySummary]
    private var maxVal: Int { days.map(\.totalGrossCents).max() ?? 1 }

    var body: some View {
        BSecCard {
            BSecHead(title: "Tagesübersicht", sub: "Letzte \(days.count) Tage")
            VStack(spacing: 0) {
                ForEach(Array(days.reversed().enumerated()), id: \.offset) { idx, day in
                    let isToday = idx == 0
                    let frac    = maxVal > 0 ? CGFloat(day.totalGrossCents) / CGFloat(maxVal) : 0
                    BDayRow(day: day, isToday: isToday, frac: frac)
                    if idx < days.count - 1 {
                        Divider()
                            .overlay(DS.C.brdLight)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

private struct BDayRow: View {
    let day:     DaySummary
    let isToday: Bool
    let frac:    CGFloat
    @State private var hovered = false

    private var dayName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "de_DE")
        guard let d = f.date(from: day.date) else { return day.date }
        if isToday { return "Heute" }
        let o = DateFormatter()
        o.dateFormat = "EEEE"
        o.locale = Locale(identifier: "de_DE")
        let s = o.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var dayDateStr: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "de_DE")
        guard let d = f.date(from: day.date) else { return "" }
        let o = DateFormatter()
        o.locale = Locale(identifier: "de_DE")
        o.dateFormat = "d. MMMM yyyy"
        return o.string(from: d)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName)
                    .font(.jakarta(12, weight: .medium))
                    .foregroundColor(isToday ? DS.C.accT : DS.C.text)
                Text(dayDateStr)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            HStack(spacing: 16) {
                Text("\(day.receiptCount) Tx")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 44, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.C.sur2)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.C.acc)
                            .opacity(isToday ? 1.0 : 0.5)
                            .frame(width: geo.size.width * frac, height: 4)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 80)
                Text(bFmtCents(day.totalGrossCents))
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(isToday ? DS.C.acc : DS.C.text)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hovered ? DS.C.bg : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Today Card (Heute mode, no byDay available)

private struct TodayCard: View {
    let report: DailyReport
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BSecCard {
            BSecHead(title: "Tagesumsatz", sub: bFmtLongDate(report.date))
            HStack(spacing: 0) {
                TodayStat(label: "Bar",   value: bFmtCents(report.paymentsCashCents))
                Rectangle().fill(DS.C.brdLight).frame(width: 1, height: 40)
                TodayStat(label: "Karte", value: bFmtCents(report.paymentsCardCents))
                Rectangle().fill(DS.C.brdLight).frame(width: 1, height: 40)
                TodayStat(label: "Bons",  value: "\(report.receiptCount)")
                Rectangle().fill(DS.C.brdLight).frame(width: 1, height: 40)
                TodayStat(label: "Stornos", value: "\(report.cancellationCount)",
                          danger: report.cancellationCount > 0)
            }
            .padding(.vertical, 16)
        }
    }
}

private struct TodayStat: View {
    let label:  String
    let value:  String
    var danger: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.jakarta(15, weight: .semibold))
                .foregroundColor(danger ? DS.C.dangerText : DS.C.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.jakarta(10, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sessions Card

private struct BSessionsCard: View {
    let sessions: [ReportSession]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BSecCard {
            BSecHead(title: "Kassensitzungen", sub: "\(sessions.count) Sitzung\(sessions.count == 1 ? "" : "en")")
            VStack(spacing: 0) {
                ForEach(sessions) { s in
                    BSessionRow(session: s)
                    if s.id != sessions.last?.id {
                        Divider()
                            .overlay(DS.C.brdLight)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

private struct BSessionRow: View {
    let session: ReportSession

    private var openedTime: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: session.openedAt) else { return session.openedAt }
        let o = DateFormatter()
        o.locale = Locale(identifier: "de_DE")
        o.dateFormat = "HH:mm"
        return o.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sitzung #\(session.id)")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Geöffnet \(openedTime) Uhr")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            if let diff = session.differenceCents {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(diff == 0 ? "±0,00 €" : (diff > 0 ? "+" : "") + bFmtCents(diff))
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(diff == 0 ? DS.C.successText : DS.C.dangerText)
                    Text("Kassendifferenz")
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }
            Text(session.status == "closed" ? "Geschlossen" : "Offen")
                .font(.jakarta(10, weight: .semibold))
                .foregroundColor(session.status == "closed" ? DS.C.text2 : DS.C.acc)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(session.status == "closed" ? DS.C.sur2 : DS.C.accBg)
                .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Zahlungsarten

private struct ZahlungsartenCard: View {
    let cashCents: Int
    let cardCents: Int

    private var total:   Int    { cashCents + cardCents }
    private var cashPct: Double { total > 0 ? Double(cashCents) / Double(total) : 0 }
    private var cardPct: Double { total > 0 ? Double(cardCents) / Double(total) : 0 }

    var body: some View {
        BSecCard {
            BSecHead(title: "Zahlungsarten", sub: nil)
            VStack(spacing: 12) {
                // Segmented bar
                if total > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            if cashPct > 0.01 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DS.C.acc)
                                    .frame(width: max(4, geo.size.width * cashPct - 1))
                            }
                            if cardPct > 0.01 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DS.C.warnText)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .frame(height: 10)
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DS.C.sur2)
                        .frame(height: 10)
                }
                // Legend
                VStack(spacing: 8) {
                    PaySplitRow(
                        color:  DS.C.acc,
                        label:  "Barzahlung",
                        pct:    Int((cashPct * 100).rounded()),
                        cents:  cashCents
                    )
                    PaySplitRow(
                        color:  DS.C.warnText,
                        label:  "Kartenzahlung",
                        pct:    Int((cardPct * 100).rounded()),
                        cents:  cardCents
                    )
                }
            }
            .padding(16)
        }
    }
}

private struct PaySplitRow: View {
    let color: Color
    let label: String
    let pct:   Int
    let cents: Int

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.jakarta(12, weight: .regular))
                .foregroundColor(DS.C.text)
            Spacer()
            Text("\(pct) %")
                .font(.jakarta(10, weight: .regular))
                .foregroundColor(DS.C.text2)
                .frame(width: 34, alignment: .trailing)
            Text(bFmtCents(cents))
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(width: 74, alignment: .trailing)
        }
    }
}

// MARK: - MwSt Card

private struct MwStCard: View {
    let vat19Net: Int
    let vat19Tax: Int
    let vat7Net:  Int
    let vat7Tax:  Int
    let vatTotal: Int

    var body: some View {
        BSecCard {
            BSecHead(title: "MwSt-Aufschlüsselung", sub: nil)
            VStack(spacing: 0) {
                if vat19Net + vat19Tax > 0 {
                    BVatRow(
                        label: "19 % Regelsteuersatz",
                        gross: vat19Net + vat19Tax,
                        net:   vat19Net,
                        tax:   vat19Tax
                    )
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                        .padding(.horizontal, 16)
                }
                if vat7Net + vat7Tax > 0 {
                    BVatRow(
                        label: "7 % Ermäßigt",
                        gross: vat7Net + vat7Tax,
                        net:   vat7Net,
                        tax:   vat7Tax
                    )
                }
                if vatTotal > 0 {
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    HStack {
                        Text("MwSt gesamt")
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Spacer()
                        Text(bFmtCents(vatTotal))
                            .font(.jakarta(14, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                if vatTotal == 0 {
                    Text("Keine Steuerdaten")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .padding(16)
                }
            }
        }
    }
}

private struct BVatRow: View {
    let label: String
    let gross: Int
    let net:   Int
    let tax:   Int

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(12, weight: .regular))
                .foregroundColor(DS.C.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(bFmtCents(gross))
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Netto \(bFmtCents(net)) · MwSt \(bFmtCents(tax))")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Stornos Card

private struct StornosCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(DS.C.dangerText)
            Text("\(count) Stornierung\(count == 1 ? "" : "en") heute")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(DS.C.dangerText)
            Spacer()
        }
        .padding(14)
        .background(DS.C.dangerBg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.C.dangerText.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Empty State

private struct BReportEmpty: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.C.text2)
            Text("Keine Daten für diesen Zeitraum")
                .font(.jakarta(14, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(DS.C.sur)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.C.brdLight, lineWidth: 1)
        )
    }
}

// MARK: - Section Card Helpers

private struct BSecCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.C.sur)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
            )
    }
}

private struct BSecHead: View {
    let title: String
    let sub:   String?

    var body: some View {
        HStack {
            Text(title)
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(DS.C.text)
            Spacer()
            if let s = sub {
                Text(s)
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Helpers

private func bFmtCents(_ cents: Int) -> String {
    let fmt = NumberFormatter()
    fmt.locale           = Locale(identifier: "de_DE")
    fmt.numberStyle      = .decimal
    fmt.minimumFractionDigits = 2
    fmt.maximumFractionDigits = 2
    return (fmt.string(from: NSNumber(value: Double(cents) / 100)) ?? "0,00") + " €"
}

private func bFmtShortCents(_ cents: Int) -> String {
    let euros = Double(cents) / 100
    let fmt   = NumberFormatter()
    fmt.locale      = Locale(identifier: "de_DE")
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 0
    return (fmt.string(from: NSNumber(value: euros)) ?? "0") + " €"
}

private func bFmtLongDate(_ iso: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "de_DE")
    guard let d = f.date(from: iso) else { return iso }
    let o = DateFormatter()
    o.locale = Locale(identifier: "de_DE")
    o.dateFormat = "d. MMMM yyyy"
    return o.string(from: d)
}

// MARK: - Previews

#Preview("Berichte — Zusammenfassung") {
    BerichteView()
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Berichte — Dark") {
    BerichteView()
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

#Preview("Berichte — Leer") {
    BerichteView()
        .environmentObject(ReportStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

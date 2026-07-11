// BerichteView.swift
// cashbox — Berichte: Umsatz, Zahlungsarten, MwSt
// Design v3: Ledger Green für Bar, Brass für Karte, Tabellenziffern,
// keine Hover-Zustände (Touch-Gerät).

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
                        .dsBannerTransition()
                }
                BToolbar(range: $range, customFrom: $customFrom, customTo: $customTo)
                if reportStore.isLoading {
                    // Skeleton im echten Berichts-Layout (KPI-Reihe + Karten)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    DSSkeleton(height: 96, cornerRadius: DS.R.card)
                                }
                            }
                            DSSkeleton(height: 220, cornerRadius: DS.R.card)
                            DSSkeleton(height: 180, cornerRadius: DS.R.card)
                        }
                        .padding(DS.S.pagePad)
                    }
                } else {
                    BContent(range: range)
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
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
        HStack(spacing: 8) {
            DSSegmentedControl(
                selection: $range,
                options: BRange.allCases.map { (value: $0, label: $0.rawValue) }
            )
            .frame(maxWidth: 420)
            Spacer()
            if range == .custom {
                HStack(spacing: 6) {
                    DatePicker("", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Text("–")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                    DatePicker("", selection: $customTo, in: customFrom...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .transition(.opacity)
            } else {
                Text(toolbarDateLabel)
                    .dsFont(.caption, monoDigits: true)
                    .foregroundColor(DS.C.text2)
            }
            // Export (PDF/DSFinV-K) kommt später — kein toter Button
            DSPill(label: "Export bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
        }
        .padding(.horizontal, DS.S.pagePad)
        .frame(height: DS.S.topbarHeight + 8)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
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
                .dsFont(.raw(14, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(isActive ? DS.C.acc : DS.C.sur2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isActive)
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
                // KPI-Reihe
                BKPIRow(
                    totalGross: totalGross,
                    receiptCnt: receiptCnt,
                    avgBon:     avgBon,
                    cancelCnt:  cancelCnt,
                    vatTotal:   vatTotal
                )
                .padding(.horizontal, DS.S.pagePad)
                .padding(.top, DS.S.pagePad)

                // Zwei Spalten
                HStack(alignment: .top, spacing: 16) {
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
                .padding(.horizontal, DS.S.pagePad)
                .padding(.top, 16)
                .padding(.bottom, DS.S.pagePad)
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
            BKPICard(label: "Umsatz (brutto)", value: euroString(totalGross), color: DS.C.accT, sub: nil)
            BKPICard(label: "Transaktionen",   value: "\(receiptCnt)",        color: DS.C.text, sub: nil)
            BKPICard(label: "Ø Bon-Wert",      value: euroString(avgBon),     color: DS.C.text, sub: nil)
            BKPICard(label: "Stornos",         value: "\(cancelCnt)",         color: cancelCnt > 0 ? DS.C.dangerText : DS.C.text, sub: nil)
            BKPICard(label: "MwSt gesamt",     value: euroString(vatTotal),   color: DS.C.text, sub: "19 % + 7 %")
        }
    }
}

private struct BKPICard: View {
    let label: String
    let value: String
    let color: Color
    let sub:   String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSSectionLabel(text: label)
                .lineLimit(1)
            Text(value)
                .dsFont(.money(22, weight: .bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(sub ?? " ")
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 16)
    }
}

// MARK: - Bar Chart

private struct BarChartCard: View {
    let days: [DaySummary]
    private var maxVal: Int { days.map(\.totalGrossCents).max() ?? 1 }

    var body: some View {
        BSecCard {
            BSecHead(title: "Umsatzverlauf", sub: "\(days.count) Tage")
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
                .frame(height: 140)
                .padding(.bottom, 6)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(DS.C.brdAdaptive),
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
        VStack(alignment: .center, spacing: 5) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.C.acc)
                .opacity(isToday ? 1.0 : 0.35)
                .frame(maxWidth: .infinity)
                .frame(height: max(4, frac * maxH))
            Text(bFmtShortCents(day.totalGrossCents))
                .dsFont(.raw(11, weight: .semibold), monoDigits: true)
                .foregroundColor(isToday ? DS.C.accT : DS.C.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .dsFont(.raw(11, weight: isToday ? .semibold : .regular))
                .foregroundColor(isToday ? DS.C.accT : DS.C.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Day Table

private struct DayTableCard: View {
    let days: [DaySummary]
    private var maxVal: Int { days.map(\.totalGrossCents).max() ?? 1 }

    var body: some View {
        BSecCard {
            BSecHead(title: "Tagesübersicht", sub: "Letzte \(days.count) Tage")
            LazyVStack(spacing: 0) {
                ForEach(Array(days.reversed().enumerated()), id: \.offset) { idx, day in
                    let isToday = idx == 0
                    let frac    = maxVal > 0 ? CGFloat(day.totalGrossCents) / CGFloat(maxVal) : 0
                    BDayRow(day: day, isToday: isToday, frac: frac)
                    if idx < days.count - 1 {
                        Divider()
                            .overlay(DS.C.brdAdaptive)
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
                    .dsFont(.subMed)
                    .foregroundColor(isToday ? DS.C.accT : DS.C.text)
                Text(dayDateStr)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            HStack(spacing: 16) {
                Text("\(day.receiptCount) Tx")
                    .dsFont(.caption, monoDigits: true)
                    .foregroundColor(DS.C.text2)
                    .frame(width: 50, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.C.sur2)
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.C.acc)
                            .opacity(isToday ? 1.0 : 0.5)
                            .frame(width: geo.size.width * frac, height: 5)
                    }
                    .frame(height: 5)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 90)
                Text(euroString(day.totalGrossCents))
                    .dsFont(.money(15, weight: .semibold))
                    .foregroundColor(isToday ? DS.C.accT : DS.C.text)
                    .frame(width: 96, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Today Card (Heute-Modus, kein byDay)

private struct TodayCard: View {
    let report: DailyReport

    var body: some View {
        BSecCard {
            BSecHead(title: "Tagesumsatz", sub: bFmtLongDate(report.date))
            HStack(spacing: 0) {
                TodayStat(label: "Bar",   value: euroString(report.paymentsCashCents))
                Rectangle().fill(DS.C.brdAdaptive).frame(width: 1, height: 44)
                TodayStat(label: "Karte", value: euroString(report.paymentsCardCents))
                Rectangle().fill(DS.C.brdAdaptive).frame(width: 1, height: 44)
                TodayStat(label: "Bons",  value: "\(report.receiptCount)")
                Rectangle().fill(DS.C.brdAdaptive).frame(width: 1, height: 44)
                TodayStat(label: "Stornos", value: "\(report.cancellationCount)",
                          danger: report.cancellationCount > 0)
            }
            .padding(.vertical, 18)
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
                .dsFont(.money(18, weight: .bold))
                .foregroundColor(danger ? DS.C.dangerText : DS.C.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sessions Card

private struct BSessionsCard: View {
    let sessions: [ReportSession]

    var body: some View {
        BSecCard {
            BSecHead(title: "Kassensitzungen", sub: "\(sessions.count) Sitzung\(sessions.count == 1 ? "" : "en")")
            LazyVStack(spacing: 0) {
                ForEach(sessions) { s in
                    BSessionRow(session: s)
                    if s.id != sessions.last?.id {
                        Divider()
                            .overlay(DS.C.brdAdaptive)
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
                    .dsFont(.subBold, monoDigits: true)
                    .foregroundColor(DS.C.text)
                Text("Geöffnet \(openedTime) Uhr")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            if let diff = session.differenceCents {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(diff == 0 ? "± 0,00 €" : (diff > 0 ? "+ " : "") + euroString(diff))
                        .dsFont(.money(14, weight: .semibold))
                        .foregroundColor(diff == 0 ? DS.C.successText : DS.C.dangerText)
                    Text("Kassendifferenz")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
            }
            DSPill(
                label: session.status == "closed" ? "Geschlossen" : "Offen",
                fg: session.status == "closed" ? DS.C.text2 : DS.C.accT,
                bg: session.status == "closed" ? DS.C.sur2 : DS.C.accBg,
                showDot: session.status != "closed"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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
            VStack(spacing: 14) {
                // Segmentierter Balken: Bar = Ledger Green, Karte = Brass
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
                                    .fill(DS.C.brass)
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
                VStack(spacing: 10) {
                    PaySplitRow(
                        color:  DS.C.acc,
                        label:  "Barzahlung",
                        pct:    Int((cashPct * 100).rounded()),
                        cents:  cashCents
                    )
                    PaySplitRow(
                        color:  DS.C.brass,
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
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .dsFont(.sub)
                .foregroundColor(DS.C.text)
            Spacer()
            Text("\(pct) %")
                .dsFont(.caption, monoDigits: true)
                .foregroundColor(DS.C.text2)
                .frame(width: 42, alignment: .trailing)
            Text(euroString(cents))
                .dsFont(.money(14, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(width: 86, alignment: .trailing)
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
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
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
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    HStack {
                        Text("MwSt gesamt")
                            .dsFont(.subBold)
                            .foregroundColor(DS.C.text)
                        Spacer()
                        Text(euroString(vatTotal))
                            .dsFont(.money(16, weight: .bold))
                            .foregroundColor(DS.C.accT)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DS.C.sur2.opacity(0.5))
                }
                if vatTotal == 0 {
                    Text("Keine Steuerdaten")
                        .dsFont(.sub)
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
                .dsFont(.sub)
                .foregroundColor(DS.C.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(euroString(gross))
                    .dsFont(.money(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Netto \(euroString(net)) · MwSt \(euroString(tax))")
                    .dsFont(.caption, monoDigits: true)
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Stornos Card

private struct StornosCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .dsFont(.raw(16))
                .foregroundColor(DS.C.dangerText)
            Text("\(count) Stornierung\(count == 1 ? "" : "en") heute")
                .dsFont(.subBold)
                .foregroundColor(DS.C.dangerText)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.dangerBg))
    }
}

// MARK: - Empty State

private struct BReportEmpty: View {
    var body: some View {
        DSEmptyState(
            icon: "chart.bar",
            title: "Keine Daten",
            message: "Für diesen Zeitraum liegen keine Umsätze vor."
        )
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
        )
    }
}

// MARK: - Section Card Helpers

private struct BSecCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.C.sur)
            .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
            )
    }
}

private struct BSecHead: View {
    let title: String
    let sub:   String?

    var body: some View {
        HStack {
            Text(title)
                .dsFont(.bodyBold)
                .foregroundColor(DS.C.text)
            Spacer()
            if let s = sub {
                Text(s)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

// MARK: - Helpers

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

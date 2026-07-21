// TableOverviewView.swift
// cashbox — Haupt-App-Shell: Topbar + Sidebar + Tischgitter
// Design v3 „Ledger Green": Status über Fläche + Pill, keine Streifen.

import SwiftUI

// MARK: - Navigation

enum NavItem: String, Hashable, CaseIterable {
    // Übersicht
    case tische       = "Tische"
    case sortiment    = "Sortiment"
    // Abrechnung
    case kassensitzung = "Kassensitzung"
    case berichte      = "Berichte"
    case zbericht      = "Z-Bericht"
    // System
    case einstellungen = "Einstellungen"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .tische:        return "square.grid.2x2"
        case .sortiment:     return "tag"
        case .kassensitzung: return "building.columns"
        case .berichte:      return "chart.bar"
        case .zbericht:      return "doc.text"
        case .einstellungen: return "gearshape"
        }
    }

    var section: NavSection {
        switch self {
        case .tische, .sortiment:                      return .uebersicht
        case .kassensitzung, .berichte, .zbericht:     return .abrechnung
        case .einstellungen:                           return .system
        }
    }
}

enum NavSection {
    case uebersicht, abrechnung, system
    var title: String {
        switch self {
        case .uebersicht:  return "Übersicht"
        case .abrechnung:  return "Abrechnung"
        case .system:      return "System"
        }
    }
}

// MARK: - Root Shell

struct TableOverviewView: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var sessionStore:   SessionStore
    @EnvironmentObject var orderStore:     OrderStore
    @EnvironmentObject var tableStore:     TableStore
    @EnvironmentObject var reportStore:    ReportStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var selectedNav:       NavItem = .tische
    @State private var selectedTable:     SelectedTable? = nil
    @State private var showSchnellkasse:  Bool = false
    @State private var schnellkasseIntent = false

    private func handleSchnellkasse() {
        if sessionStore.hasOpenSession {
            showSchnellkasse = true
        } else {
            schnellkasseIntent = true
            withAnimation(DS.M.base) { selectedNav = .kassensitzung }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                AppTopBar(selectedNav: $selectedNav)

                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .dsBannerTransition()
                }

                HStack(spacing: 0) {
                    AppSidebar(selectedNav: $selectedNav, onSchnellkasse: handleSchnellkasse)
                        .frame(width: DS.S.sidebarWidth)

                    Rectangle()
                        .fill(DS.C.brdAdaptive)
                        .frame(width: 1)

                    AppContent(selectedNav: selectedNav, onTableTap: { id, name in
                        selectedTable = SelectedTable(id: id, name: name)
                    }, onSchnellkasse: handleSchnellkasse)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .task {
            async let t: () = tableStore.loadTables()
            async let s: () = sessionStore.loadCurrent()
            async let r: () = reportStore.loadDaily()
            _ = await (t, s, r)
        }
        .onChange(of: sessionStore.hasOpenSession) {
            if sessionStore.hasOpenSession && schnellkasseIntent {
                schnellkasseIntent = false
                showSchnellkasse   = true
            }
        }
        .fullScreenCover(item: $selectedTable) { table in
            OrderView(tableId: table.id, tableName: table.name)
        }
        .fullScreenCover(isPresented: $showSchnellkasse) {
            OrderView(tableId: nil, tableName: nil)
        }
        .onChange(of: selectedTable) {
            if selectedTable == nil {
                Task {
                    async let t: () = tableStore.loadTables()
                    async let r: () = reportStore.loadDaily()
                    _ = await (t, r)
                }
            }
        }
        .onChange(of: showSchnellkasse) {
            if !showSchnellkasse {
                Task {
                    async let t: () = tableStore.loadTables()
                    async let r: () = reportStore.loadDaily()
                    _ = await (t, r)
                }
            }
        }
    }
}

private struct SelectedTable: Identifiable, Equatable {
    let id:   Int
    let name: String
}

// MARK: - Topbar

private struct AppTopBar: View {
    @EnvironmentObject var authStore:    AuthStore
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var selectedNav: NavItem
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.system.rawValue

    private var appearance: DSAppearance { DSAppearance(rawValue: appearanceRaw) ?? .system }

    private var appearanceIcon: String {
        switch appearance {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                AppBrandMark()
                Text("cashbox")
                    .dsFont(.raw(18, weight: .bold))
                    .foregroundColor(DS.C.text)
            }
            .padding(.horizontal, 16)
            .frame(width: DS.S.sidebarWidth, alignment: .leading)

            Rectangle()
                .fill(DS.C.brdAdaptive)
                .frame(width: 1, height: 24)

            Spacer()

            // Session chip
            SessionChip(selectedNav: $selectedNav)

            Spacer().frame(width: 20)

            // User
            if let user = authStore.currentUser {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(DS.C.sur2)
                            .frame(width: 32, height: 32)
                        Text(String(user.name.prefix(1)).uppercased())
                            .dsFont(.captionBold)
                            .foregroundColor(DS.C.text)
                    }
                    Text(user.name)
                        .dsFont(.subMed)
                        .foregroundColor(DS.C.text)
                }
                Spacer().frame(width: 16)
            }

            // Darstellung: System → Hell → Dunkel (zyklisch), 44pt Trefferfläche
            Button {
                let all = DSAppearance.allCases
                let idx = all.firstIndex(of: appearance) ?? 0
                withAnimation(DS.M.base) {
                    appearanceRaw = all[(idx + 1) % all.count].rawValue
                }
            } label: {
                Image(systemName: appearanceIcon)
                    .dsFont(.raw(16, weight: .medium))
                    .foregroundColor(DS.C.text2)
                    .frame(width: DS.S.touchTarget, height: DS.S.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Darstellung wechseln, aktuell \(appearance.label)")

            Spacer().frame(width: 10)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

private struct SessionChip: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var selectedNav: NavItem

    var body: some View {
        if !sessionStore.hasLoaded {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .frame(width: 32, height: 22)
        } else if let session = sessionStore.currentSession {
            DSPill(
                label: "Schicht offen · \(formattedTime(session.openedAt))",
                fg: DS.C.accT,
                bg: DS.C.accBg
            )
        } else {
            Button {
                withAnimation(DS.M.base) { selectedNav = .kassensitzung }
            } label: {
                DSPill(
                    label: "Kasse geschlossen — tippen zum Öffnen",
                    fg: DS.C.brassText,
                    bg: DS.C.brassBg
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func formattedTime(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: isoString) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: isoString)
        }()
        guard let date else { return "--:--" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Sidebar

private struct AppSidebar: View {
    @EnvironmentObject var authStore:    AuthStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tableStore:   TableStore
    @Binding var selectedNav: NavItem
    let onSchnellkasse: () -> Void

    // Backend erlaubt Produkt-/Kategorien-Schreibzugriff und Berichte nur für
    // owner+manager (403 für staff) — staff sieht die Bereiche gar nicht erst.
    private var sections: [(NavSection, [NavItem])] {
        let isStaff = authStore.currentUser?.role == .staff
        if isStaff {
            return [
                (.uebersicht,  [.tische]),
                (.abrechnung,  [.kassensitzung]),
            ]
        }
        return [
            (.uebersicht,  [.tische, .sortiment]),
            (.abrechnung,  [.kassensitzung, .berichte, .zbericht]),
            (.system,      [.einstellungen]),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.0.title) { _, pair in
                        let (section, items) = pair
                        SidebarSection(
                            title: section.title,
                            items: items,
                            selectedNav: $selectedNav,
                            badgeFor: { item in
                                item == .tische ? String(tableStore.tables.count) : nil
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            SidebarKPIs()
            SidebarLogout()
        }
        .frame(maxHeight: .infinity)
        .background(DS.C.sur)
    }
}

private struct SidebarSection: View {
    let title: String
    let items: [NavItem]
    @Binding var selectedNav: NavItem
    var badgeFor: (NavItem) -> String? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DSSectionLabel(text: title)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ForEach(items, id: \.self) { item in
                SidebarNavRow(
                    item: item,
                    badge: badgeFor(item),
                    isSelected: selectedNav == item
                ) {
                    withAnimation(DS.M.base) { selectedNav = item }
                }
            }
        }
    }
}

private struct SidebarNavRow: View {
    let item:       NavItem
    var badge:      String? = nil
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .dsFont(.raw(17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                    .frame(width: 24)
                Text(item.label)
                    .dsFont(.raw(16, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Spacer()
                if let badge {
                    Text(badge)
                        .dsFont(.captionBold, monoDigits: true)
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(isSelected ? DS.C.sur : DS.C.sur2))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .fill(isSelected ? DS.C.accBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isSelected)
    }
}

private struct SidebarKPIs: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tableStore:   TableStore
    @EnvironmentObject var reportStore:  ReportStore

    @State private var shiftDuration = "–"
    @State private var durationTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                DSSectionLabel(text: "Umsatz heute")
                if reportStore.isLoading {
                    Text("…")
                        .dsFont(.moneyDisplay(30))
                        .foregroundColor(DS.C.text2)
                } else {
                    MoneyText(
                        cents: reportStore.dailyReport?.totalGrossCents ?? 0,
                        size: 30, weight: .bold, color: DS.C.accT
                    )
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    DSSectionLabel(text: "Tische")
                    Text("\(tableStore.occupiedCount)/\(tableStore.tables.count)")
                        .dsFont(.raw(21, weight: .bold), monoDigits: true)
                        .foregroundColor(DS.C.text)
                }
                VStack(alignment: .leading, spacing: 3) {
                    DSSectionLabel(text: "Schicht")
                    Text(sessionStore.hasOpenSession ? shiftDuration : "–")
                        .dsFont(.raw(21, weight: .bold), monoDigits: true)
                        .foregroundColor(DS.C.text)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .top
        )
        .onAppear {
            updateDuration()
            durationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in updateDuration() }
            }
        }
        .onDisappear {
            durationTimer?.invalidate()
            durationTimer = nil
        }
        .onChange(of: sessionStore.currentSession?.id) { updateDuration() }
    }

    private func updateDuration() {
        guard let openedAt = sessionStore.currentSession?.openedAt else {
            shiftDuration = "–"; return
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let start = iso.date(from: openedAt) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: openedAt)
        }()
        guard let start else { shiftDuration = "–"; return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        shiftDuration = String(format: "%d:%02d h", h, m)
    }
}

private struct SidebarLogout: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        Button {
            Task { authStore.logout() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .dsFont(.raw(16, weight: .regular))
                    .frame(width: 24)
                Text("Abmelden")
                    .dsFont(.subMed)
            }
            .foregroundColor(DS.C.text2)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .top
        )
    }
}

// MARK: - Content Area (Router)

private struct AppContent: View {
    let selectedNav:    NavItem
    let onTableTap:     (Int, String) -> Void
    let onSchnellkasse: () -> Void

    var body: some View {
        Group {
            switch selectedNav {
            case .tische:
                TableGridContent(onTableTap: onTableTap, onSchnellkasse: onSchnellkasse)
            case .kassensitzung:
                KassensitzungView()
            case .zbericht:
                ZBerichtView()
            case .berichte:
                BerichteView()
            case .sortiment:
                SortimentView()
            case .einstellungen:
                EinstellungenView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tischgitter

private struct TableGridContent: View {
    @EnvironmentObject var tableStore:   TableStore
    @EnvironmentObject var sessionStore: SessionStore
    let onTableTap:     (Int, String) -> Void
    let onSchnellkasse: () -> Void

    @State private var selectedZoneId: Int? = nil
    @State private var now = Date()
    @State private var minuteTimer: Timer?

    private var filteredTables: [TableItem] {
        guard let zoneId = selectedZoneId else { return tableStore.tables }
        return tableStore.tables.filter { $0.zone?.id == zoneId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zone-Filter-Pills
            if !tableStore.zones.isEmpty {
                ZonePillsBar(zones: tableStore.zones, selectedZoneId: $selectedZoneId)
            }

            // Kein-Session-Hinweis
            if !sessionStore.hasOpenSession {
                NoSessionBanner()
            }

            // Tisch-Grid — Ladezustand als Skeleton im echten Kachel-Layout
            if tableStore.isLoading {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                        spacing: 14
                    ) {
                        ForEach(0..<6, id: \.self) { _ in
                            DSSkeleton(height: 176, cornerRadius: DS.R.card)
                        }
                    }
                    .padding(DS.S.pagePad)
                }
            } else if tableStore.tables.isEmpty {
                DSEmptyState(
                    icon: "square.grid.2x2",
                    title: "Keine Tische angelegt",
                    message: "Tische können in den Einstellungen hinzugefügt werden."
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                        spacing: 16
                    ) {
                        ForEach(filteredTables) { table in
                            let status: TableCardStatus = {
                                if table.openOrdersCount == 0 { return .frei }
                                if tableStore.payingTableIds.contains(table.id) { return .zahlung }
                                return .besetzt
                            }()
                            TableCard(table: table, status: status, now: now) {
                                onTableTap(table.id, table.name)
                            }
                        }
                    }
                    .padding(DS.S.pagePad)
                }
                .refreshable { await tableStore.loadTables() }
            }

            // Schnellkasse — fixiert am unteren Rand
            SchnellkasseButton(onTap: onSchnellkasse)
        }
        .onAppear {
            now = Date()
            minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in now = Date() }
            }
        }
        .onDisappear {
            minuteTimer?.invalidate()
            minuteTimer = nil
        }
        .background(DS.C.bg)
    }
}

private struct NoSessionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DS.C.brass)
                .dsFont(.raw(14))
            Text("Keine offene Kassensitzung — Bestellungen können erst nach Kasseneröffnung erstellt werden.")
                .dsFont(.sub)
                .foregroundColor(DS.C.brassText)
            Spacer()
        }
        .padding(.horizontal, DS.S.pagePad)
        .padding(.vertical, 12)
        .background(DS.C.brassBg)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

// MARK: - Schnellkasse Button

private struct SchnellkasseButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .dsFont(.raw(18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Schnellkasse")
                        .dsFont(.raw(17, weight: .bold))
                        .foregroundColor(.white)
                    Text("Ohne Tisch — Direktverkauf")
                        .dsFont(.raw(14, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .dsFont(.raw(15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: DS.R.quickBanner).fill(DS.C.acc))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .top
        )
    }
}

// MARK: - Zone Filter Pills

private struct ZonePillsBar: View {
    let zones: [TableZone]
    @Binding var selectedZoneId: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ZonePill(label: "Alle", isSelected: selectedZoneId == nil) {
                    withAnimation(DS.M.base) { selectedZoneId = nil }
                }
                ForEach(zones) { zone in
                    ZonePill(label: zone.name, isSelected: selectedZoneId == zone.id) {
                        withAnimation(DS.M.base) { selectedZoneId = zone.id }
                    }
                }
            }
            .padding(.horizontal, DS.S.pagePad)
            .padding(.vertical, 12)
        }
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

private struct ZonePill: View {
    let label:      String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .dsFont(.raw(14, weight: .semibold))
                .foregroundColor(isSelected ? .white : DS.C.text)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(isSelected ? DS.C.acc : DS.C.sur2))
                // Trefferfläche ≥ 44pt — Optik bleibt 38pt
                .frame(minHeight: DS.S.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Tischkachel
// frei    → ruhige Karte, nur Name + dezenter Status
// besetzt → Betrag dominiert in Ledger Green
// zahlung → Brass-Fläche: der Gast wartet, Kachel ruft

private struct TableCard: View {
    let table:  TableItem
    let status: TableCardStatus
    let now:    Date
    let onTap:  () -> Void

    private var minutesOpen: Int? {
        guard let oldest = table.oldestOrderAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: oldest) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: oldest)
        }()
        guard let date else { return nil }
        return max(0, Int(now.timeIntervalSince(date)) / 60)
    }

    private var cardBg: Color {
        switch status {
        case .frei:    return DS.C.sur
        case .besetzt: return DS.C.sur
        case .zahlung: return DS.C.billBg
        }
    }

    private var cardBorder: Color {
        status == .zahlung ? DS.C.brass.opacity(0.45) : DS.C.brdAdaptive
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Kopf: Tischname + Status-Pill
                HStack(alignment: .center) {
                    Text(table.name)
                        .dsFont(.heading)
                        .foregroundColor(DS.C.text)
                        .lineLimit(1)
                    Spacer()
                    statusPill
                }

                Spacer(minLength: 12)

                // Betrag (dominant) oder ruhiger Frei-Zustand
                if status != .frei {
                    MoneyText(
                        cents: table.totalOpenCents,
                        size: 40,
                        weight: .bold,
                        color: status == .zahlung ? DS.C.brassText : DS.C.text
                    )
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .dsFont(.raw(22, weight: .medium))
                        .foregroundColor(DS.C.text2.opacity(0.6))
                }

                Spacer(minLength: 12)

                // Fußzeile: Zeit + Positionen
                HStack {
                    if status == .frei {
                        Text(table.zone?.name ?? "Tippen zum Bestellen")
                            .foregroundColor(DS.C.text2)
                        Spacer()
                    } else {
                        Text(minutesOpen.map { "\($0) min" } ?? "—")
                            .monospacedDigit()
                            .foregroundColor(status == .zahlung ? DS.C.brassText.opacity(0.8) : DS.C.text2)
                        Spacer()
                        let posText = table.totalOpenItems == 1 ? "1 Position" : "\(table.totalOpenItems) Positionen"
                        Text(posText)
                            .monospacedDigit()
                            .foregroundColor(status == .zahlung ? DS.C.brassText.opacity(0.8) : DS.C.text2)
                    }
                }
                .dsFont(.raw(14, weight: .medium))
            }
            .padding(DS.S.cardPad)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(cardBg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(cardBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
        }
        .buttonStyle(TableCardPressStyle())
        // VoiceOver: ein Element mit kombinierter Ansage statt vier Einzelteilen
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilitySummary: String {
        switch status {
        case .frei:
            return "Tisch \(table.name), frei"
        case .besetzt:
            return "Tisch \(table.name), besetzt, \(euroAccessibilityLabel(table.totalOpenCents))"
        case .zahlung:
            return "Tisch \(table.name), Zahlung angefordert, \(euroAccessibilityLabel(table.totalOpenCents))"
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch status {
        case .frei:
            Text("Frei")
                .dsFont(.captionBold)
                .foregroundColor(DS.C.text2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(DS.C.sur2))
        case .besetzt:
            DSPill(label: "Besetzt", fg: DS.C.accT, bg: DS.C.accBg)
        case .zahlung:
            DSPill(label: "Zahlung", fg: DS.C.brassText, bg: DS.C.brassBg)
        }
    }
}

/// Press-Feedback der Tischkachel: leichtes Zusammendrücken statt Farbwechsel
private struct TableCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

// Lokales Status-Enum für die Darstellung der Tischkachel
enum TableCardStatus {
    case frei, besetzt, zahlung
}

// MARK: - Brand Mark

struct AppBrandMark: View {
    var size: CGFloat = DS.S.brandMarkSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.R.brandMark)
                .fill(DS.C.acc)
                .frame(width: size, height: size)
            // Kassenlade-Glyphe — proportional zum festen Logo-Rahmen,
            // skaliert bewusst NICHT mit Dynamic Type (dokumentierte Ausnahme)
            Image(systemName: "eurosign")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Previews

#Preview("Tischübersicht — mit Tischen") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Keine Kassensitzung") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.previewNoSession)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.preview)
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Leer — keine Tische") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.previewEmpty)
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.preview)
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(ReportStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

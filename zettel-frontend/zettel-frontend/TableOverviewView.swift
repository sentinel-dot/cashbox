// TableOverviewView.swift
// cashbox — Haupt-App-Shell: Topbar + Sidebar + Tischgitter
// Design: kassensystem-design-system.md §3–4

import SwiftUI

// MARK: - Navigation

enum NavItem: String, Hashable, CaseIterable {
    // Übersicht
    case tische       = "Tische"
    case produkte     = "Produkte"
    case kategorien   = "Kategorien"
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
        case .produkte:      return "tag"
        case .kategorien:    return "folder"
        case .kassensitzung: return "building.columns"
        case .berichte:      return "chart.bar"
        case .zbericht:      return "doc.text"
        case .einstellungen: return "gearshape"
        }
    }

    var section: NavSection {
        switch self {
        case .tische, .produkte, .kategorien:          return .uebersicht
        case .kassensitzung, .berichte, .zbericht:     return .abrechnung
        case .einstellungen:                           return .system
        }
    }
}

enum NavSection {
    case uebersicht, abrechnung, system
    var title: String {
        switch self {
        case .uebersicht:  return "ÜBERSICHT"
        case .abrechnung:  return "ABRECHNUNG"
        case .system:      return "SYSTEM"
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

    @AppStorage("prefersDarkMode") private var prefersDarkMode = false

    @State private var selectedNav:       NavItem = .tische
    @State private var selectedTable:     SelectedTable? = nil
    @State private var showSchnellkasse:  Bool = false
    @State private var schnellkasseIntent = false

    private func handleSchnellkasse() {
        if sessionStore.hasOpenSession {
            showSchnellkasse = true
        } else {
            schnellkasseIntent = true
            withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .kassensitzung }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                AppTopBar(selectedNav: $selectedNav)

                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    AppSidebar(selectedNav: $selectedNav, onSchnellkasse: handleSchnellkasse)
                        .frame(width: DS.S.sidebarWidth)

                    Rectangle()
                        .fill(DS.C.brdLight)
                        .frame(width: 1)

                    AppContent(selectedNav: selectedNav, onTableTap: { id, name in
                        selectedTable = SelectedTable(id: id, name: name)
                    }, onSchnellkasse: handleSchnellkasse)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(prefersDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
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
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false

    var body: some View {
        HStack(spacing: 0) {
            // Brand
            HStack(spacing: 8) {
                AppBrandMark()
                Text("Kassensystem")
                    .font(.jakarta(DS.T.topbarAppName, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }
            .padding(.horizontal, 16)
            .frame(width: DS.S.sidebarWidth, alignment: .leading)

            Rectangle()
                .fill(DS.C.brdLight)
                .frame(width: 1, height: 24)

            Spacer()

            // User name
            if let user = authStore.currentUser {
                Text(user.name)
                    .font(.jakarta(DS.T.navItem, weight: .medium))
                    .foregroundColor(DS.C.text)
                Spacer().frame(width: 16)
            }

            // Session chip
            SessionChip(selectedNav: $selectedNav)

            Spacer().frame(width: 16)

            // Dark mode toggle
            Toggle("", isOn: $prefersDarkMode)
                .toggleStyle(.switch)
                .tint(DS.C.text2)
                .labelsHidden()
                .scaleEffect(0.85)

            Spacer().frame(width: 16)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
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
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Schicht offen · \(formattedTime(session.openedAt))")
                    .font(.jakarta(DS.T.sessionChip, weight: .semibold))
                    .foregroundColor(DS.C.accT)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.C.accBg)
            .cornerRadius(20)
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .kassensitzung }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Kasse geschlossen — tippen zum Öffnen")
                        .font(.jakarta(DS.T.sessionChip, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(20)
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

    private let sections: [(NavSection, [NavItem])] = [
        (.uebersicht,  [.tische, .produkte, .kategorien]),
        (.abrechnung,  [.kassensitzung, .berichte, .zbericht]),
        (.system,      [.einstellungen]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.0.title) { index, pair in
                        let (section, items) = pair
                        if index > 0 {
                            Rectangle()
                                .fill(DS.C.brdLight)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
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
                .padding(.top, 8)
                .padding(.bottom, 8)
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
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.jakarta(13, weight: .medium))
                .foregroundColor(DS.C.text2)
                .tracking(0.8)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 6)

            ForEach(items, id: \.self) { item in
                SidebarNavRow(
                    item: item,
                    badge: badgeFor(item),
                    isSelected: selectedNav == item
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedNav = item }
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
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.C.acc : DS.C.text2)
                    .frame(width: 22)
                Text(item.label)
                    .font(.jakarta(17, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.badge)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DS.C.accBg : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(DS.C.acc)
                        .frame(width: 3)
                        .cornerRadius(1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct SidebarKPIs: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tableStore:   TableStore
    @EnvironmentObject var reportStore:  ReportStore

    @State private var shiftDuration = "–"
    @State private var durationTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KPIBlock(
                label: "UMSATZ HEUTE",
                value: reportStore.isLoading ? "…" : formatCents(reportStore.dailyReport?.totalGrossCents ?? 0),
                accent: true
            )
            KPIBlock(
                label: "OFFENE TISCHE",
                value: "\(tableStore.occupiedCount) / \(tableStore.tables.count)"
            )
            KPIBlock(
                label: "SCHICHTDAUER",
                value: sessionStore.hasOpenSession ? shiftDuration : "–"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
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

    private func formatCents(_ cents: Int) -> String {
        "\(cents / 100),\(String(format: "%02d", cents % 100)) €"
    }
}

private struct KPIBlock: View {
    let label: String
    let value: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.jakarta(13, weight: .medium))
                .foregroundColor(DS.C.text2)
                .tracking(0.8)
            Text(value)
                .font(.jakarta(38, weight: .bold))
                .foregroundColor(accent ? DS.C.acc : DS.C.text)
                .tracking(-0.8)
        }
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
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22)
                Text("Abmelden")
                    .font(.jakarta(17, weight: .regular))
            }
            .foregroundColor(DS.C.text2)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
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
            case .produkte:
                ProdukteView()
            case .kategorien:
                KategorienView()
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

            // Tisch-Grid
            if tableStore.isLoading {
                Spacer()
                ProgressView().progressViewStyle(.circular).scaleEffect(1.2)
                Spacer()
            } else if tableStore.tables.isEmpty {
                EmptyTablesPlaceholder()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
                        spacing: 20
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
                    .padding(20)
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
                .foregroundColor(.orange)
                .font(.system(size: 13))
            Text("Keine offene Kassensitzung — Bestellungen können erst nach Kasseneröffnung erstellt werden.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.2)),
            alignment: .bottom
        )
    }
}

private struct EmptyTablesPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(DS.C.text2)
            Text("Keine Tische angelegt")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text("Tische können in den Einstellungen hinzugefügt werden.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Schnellkasse Button

private struct SchnellkasseButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 46, height: 46)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Schnellkasse")
                        .font(.jakarta(19, weight: .bold))
                        .foregroundColor(.white)
                    Text("Ohne Tisch — Direktverkauf")
                        .font(.jakarta(15, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [DS.C.acc, DS.C.acc.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(DS.R.quickBanner)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .top
        )
    }
}

// MARK: - Zone Filter Pills

private struct ZonePillsBar: View {
    let zones: [TableZone]
    @Binding var selectedZoneId: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ZonePill(label: "Alle", isSelected: selectedZoneId == nil) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedZoneId = nil }
                }
                ForEach(zones) { zone in
                    ZonePill(label: zone.name, isSelected: selectedZoneId == zone.id) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedZoneId = zone.id }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct ZonePill: View {
    let label:      String
    let isSelected: Bool
    let onTap:      () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(DS.T.zonePill, weight: .semibold))
                .foregroundColor(isSelected ? .white : DS.C.text2)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(isSelected ? DS.C.acc : Color.clear)
                .cornerRadius(DS.R.badge)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.R.badge)
                        .strokeBorder(
                            isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tischkachel

private struct TableCard: View {
    let table:  TableItem
    let status: TableCardStatus
    let now:    Date
    let onTap:  () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var stripeColor: Color? {
        switch status {
        case .frei:    return nil
        case .besetzt: return DS.C.stripeBusy
        case .zahlung: return DS.C.stripeBill
        }
    }

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

    private var amountText: String {
        "\(table.totalOpenCents / 100),\(String(format: "%02d", table.totalOpenCents % 100)) €"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left status stripe
                if let stripe = stripeColor {
                    Rectangle()
                        .fill(stripe)
                        .frame(width: 8)
                }

                // Card content
                VStack(alignment: .leading, spacing: 0) {
                    // Row 1: Table name + status badge
                    HStack(alignment: .center) {
                        Text(table.name)
                            .font(.jakarta(22, weight: .bold))
                            .foregroundColor(DS.C.text)
                            .lineLimit(1)
                        Spacer()
                        TableStatusBadge(status: status)
                    }

                    // Row 2: Amount (dominant)
                    if status != .frei {
                        Text(amountText)
                            .font(.jakarta(52, weight: .bold))
                            .foregroundColor(DS.C.text)
                            .tracking(-1.5)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .padding(.top, 12)
                    } else {
                        Spacer().frame(height: 12)
                    }

                    Spacer(minLength: 20)

                    // Divider
                    Rectangle()
                        .fill(DS.C.brdLight)
                        .frame(height: 1)

                    // Row 3: Footer — time left, positions right
                    HStack {
                        if status == .frei {
                            Text("Verfügbar")
                                .foregroundColor(DS.C.freeText)
                            Spacer()
                        } else {
                            Text(minutesOpen.map { "\($0) min" } ?? "—")
                                .foregroundColor(DS.C.text2)
                            Spacer()
                            let posText = table.totalOpenItems == 1 ? "1 Position" : "\(table.totalOpenItems) Positionen"
                            Text(posText)
                                .foregroundColor(DS.C.text2)
                        }
                    }
                    .font(.jakarta(17, weight: .medium))
                    .padding(.top, 12)
                }
                .padding(22)
            }
        }
        .buttonStyle(.plain)
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
        .frame(minHeight: 210)
    }
}

private struct TableStatusBadge: View {
    let status: TableCardStatus

    private var dotColor: Color {
        switch status {
        case .frei:    return DS.C.freeText
        case .besetzt: return DS.C.busyText
        case .zahlung: return DS.C.billText
        }
    }

    private var label: String {
        switch status {
        case .frei:    return "Frei"
        case .besetzt: return "Besetzt"
        case .zahlung: return "Zahlung"
        }
    }

    private var bg: Color {
        switch status {
        case .frei:    return DS.C.freeBg
        case .besetzt: return DS.C.busyBg
        case .zahlung: return DS.C.billBg
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.jakarta(15, weight: .semibold))
                .foregroundColor(dotColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(bg)
        .cornerRadius(DS.R.badge)
        .fixedSize()
    }
}

// Lokales Status-Enum für die Darstellung der Tischkachel
enum TableCardStatus {
    case frei, besetzt, zahlung
}

// Linke Border der Tischkachel — offener Pfad: Oben-links-Bogen → linke Kante → Unten-links-Bogen
private struct LeftBorder: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addArc(center: CGPoint(x: r, y: r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: rect.height - r))
        path.addArc(center: CGPoint(x: r, y: rect.height - r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        return path
    }
}


// MARK: - Brand Mark (lokal — LoginView hat eigene private Version)

private struct AppBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.R.brandMark)
                .fill(DS.C.acc)
                .frame(width: DS.S.brandMarkSize, height: DS.S.brandMarkSize)
            Text("cb")
                .font(.jakarta(13, weight: .bold))
                .foregroundColor(.white)
                .tracking(-0.5)
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

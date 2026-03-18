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
        .onChange(of: sessionStore.hasOpenSession) { isOpen in
            if isOpen && schnellkasseIntent {
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
    }
}

private struct SelectedTable: Identifiable {
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
                    ForEach(sections, id: \.0.title) { section, items in
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
                .font(.jakarta(DS.T.sectionHeader, weight: .regular))
                .foregroundColor(DS.C.text2)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

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
            HStack(spacing: 0) {
                Text(item.label)
                    .font(.jakarta(DS.T.navItem, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.jakarta(DS.T.badge, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.badge)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DS.C.accBg : Color.clear)
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
        VStack(alignment: .leading, spacing: 12) {
            KPIBlock(
                label: "UMSATZ HEUTE",
                value: reportStore.dailyReport.map { formatCents($0.totalGrossCents) } ?? "–",
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        .onChange(of: sessionStore.currentSession?.id) { _ in updateDuration() }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.jakarta(DS.T.kpiLabel, weight: .regular))
                .foregroundColor(DS.C.text2)
                .tracking(0.6)
            Text(value)
                .font(.jakarta(DS.T.kpiValue, weight: .semibold))
                .foregroundColor(accent ? DS.C.acc : DS.C.text)
        }
    }
}

private struct SidebarLogout: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        Button {
            Task { authStore.logout() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11, weight: .regular))
                Text("Abmelden")
                    .font(.jakarta(DS.T.navItem, weight: .regular))
            }
            .foregroundColor(DS.C.text2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        ForEach(filteredTables) { table in
                            let status: TableCardStatus = {
                                if table.openOrdersCount == 0 { return .frei }
                                if tableStore.payingTableIds.contains(table.id) { return .zahlung }
                                return .besetzt
                            }()
                            TableCard(table: table, status: status) {
                                onTableTap(table.id, table.name)
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await tableStore.loadTables() }
            }

            // Schnellkasse — fixiert am unteren Rand
            SchnellkasseButton(onTap: onSchnellkasse)
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
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schnellkasse starten")
                        .font(.jakarta(DS.T.quickLabel, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Ohne Tisch — Theke oder Außer-Haus")
                        .font(.jakarta(DS.T.quickSub, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(DS.C.acc)
            .cornerRadius(DS.R.quickBanner)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
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
    let onTap:  () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        switch status {
        case .frei:    return DS.C.sur
        case .besetzt: return DS.C.busyBg
        case .zahlung: return DS.C.billBg
        }
    }

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
        return max(0, Int(Date().timeIntervalSince(date)) / 60)
    }

    private var amountText: String {
        "\(table.totalOpenCents / 100),\(String(format: "%02d", table.totalOpenCents % 100)) €"
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                bgColor

                VStack(alignment: .leading, spacing: 0) {
                    // Zeile 1: Tischname + Badge
                    HStack(alignment: .center) {
                        Text(table.name)
                            .font(.jakarta(DS.T.tableName, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .lineLimit(1)
                        Spacer()
                        TableStatusBadge(status: status)
                    }
                    .padding(.bottom, 10)

                    // Zeile 2: Betrag
                    if status != .frei {
                        Text(amountText)
                            .font(.jakarta(DS.T.tableAmount, weight: .bold))
                            .foregroundColor(DS.C.text)
                    } else {
                        Text("—")
                            .font(.jakarta(DS.T.tableAmount, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                    }

                    Spacer().frame(minHeight: 10)

                    // Trennlinie
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(DS.C.brd(colorScheme))
                        .padding(.bottom, 8)

                    // Zeile 3: Meta mit Dot-Separator
                    if status == .frei {
                        Text("verfügbar")
                            .font(.jakarta(DS.T.tableMeta, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    } else {
                        HStack(spacing: 5) {
                            if let min = minutesOpen {
                                Text("\(min) min")
                                    .font(.jakarta(DS.T.tableMeta, weight: .regular))
                                    .foregroundColor(DS.C.text2)
                                Circle()
                                    .fill(DS.C.brd(colorScheme))
                                    .frame(width: 3, height: 3)
                            }
                            let itemText = table.totalOpenItems == 1
                                ? "1 Position"
                                : "\(table.totalOpenItems) Positionen"
                            Text(itemText)
                                .font(.jakarta(DS.T.tableMeta, weight: .regular))
                                .foregroundColor(DS.C.text2)
                        }
                    }
                }
                .padding(14)

                // Linker Akzent-Streifen
                if let stripe = stripeColor {
                    Rectangle()
                        .fill(stripe)
                        .frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
        .frame(minHeight: 140)
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
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.jakarta(DS.T.badge, weight: .semibold))
                .foregroundColor(dotColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(bg)
        .cornerRadius(DS.R.badge)
        .fixedSize()
    }
}

// Lokales Status-Enum für die Darstellung der Tischkachel
enum TableCardStatus {
    case frei, besetzt, zahlung
}

// MARK: - Brand Mark (lokal — LoginView hat eigene private Version)

private struct AppBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.R.brandMark)
                .fill(DS.C.acc)
                .frame(width: DS.S.brandMarkSize, height: DS.S.brandMarkSize)
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white).frame(width: 5, height: 5)
                }
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white).frame(width: 5, height: 5)
                }
            }
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

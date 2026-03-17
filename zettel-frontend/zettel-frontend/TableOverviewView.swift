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
        case .kassensitzung: return "tray.full"
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
    @EnvironmentObject var authStore:    AuthStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var orderStore:   OrderStore
    @EnvironmentObject var tableStore:   TableStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var selectedNav:   NavItem = .tische
    @State private var selectedTable: SelectedTable? = nil

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
                    AppSidebar(selectedNav: $selectedNav)
                        .frame(width: DS.S.sidebarWidth)

                    Rectangle()
                        .fill(DS.C.brdLight)
                        .frame(width: 1)

                    AppContent(selectedNav: selectedNav) { id, name in
                        selectedTable = SelectedTable(id: id, name: name)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .task { await tableStore.loadTables() }
        .fullScreenCover(item: $selectedTable) { table in
            OrderView(tableId: table.id, tableName: table.name)
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

    var body: some View {
        HStack(spacing: 0) {
            // Brand (linksbündig in Sidebar-Breite)
            HStack(spacing: 8) {
                AppBrandMark()
                Text("cashbox")
                    .font(.jakarta(DS.T.topbarAppName, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }
            .padding(.horizontal, 16)
            .frame(width: DS.S.sidebarWidth, alignment: .leading)

            Rectangle()
                .fill(DS.C.brdLight)
                .frame(width: 1, height: 24)

            Spacer()

            // Session-Chip
            SessionChip(selectedNav: $selectedNav)

            Spacer().frame(width: 20)

            // User-Avatar
            if let user = authStore.currentUser {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(user.role == .owner ? DS.C.accBg : DS.C.sur2)
                            .frame(width: DS.S.avatarSize, height: DS.S.avatarSize)
                        Text(String(user.name.prefix(1)).uppercased())
                            .font(.jakarta(11, weight: .semibold))
                            .foregroundColor(user.role == .owner ? DS.C.accT : DS.C.text2)
                    }
                    Text(user.name)
                        .font(.jakarta(DS.T.navItem, weight: .medium))
                        .foregroundColor(DS.C.text)
                }
            }

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
        if sessionStore.hasOpenSession {
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Schicht offen")
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
                    Text("Keine Schicht — tippen zum Öffnen")
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
}

// MARK: - Sidebar

private struct AppSidebar: View {
    @EnvironmentObject var authStore:    AuthStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tableStore:   TableStore
    @Binding var selectedNav: NavItem

    private let sections: [(NavSection, [NavItem])] = [
        (.uebersicht,  [.tische, .produkte, .kategorien]),
        (.abrechnung,  [.kassensitzung, .berichte, .zbericht]),
        (.system,      [.einstellungen]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Nav-Items (scrollbar)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.0.title) { section, items in
                        SidebarSection(title: section.title, items: items, selectedNav: $selectedNav)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

            // Schnellkasse-Banner
            SchnellkasseBanner()

            // KPI-Block
            SidebarKPIs()

            // Logout
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
                SidebarNavRow(item: item, isSelected: selectedNav == item) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedNav = item }
                }
            }
        }
    }
}

private struct SidebarNavRow: View {
    let item:       NavItem
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .frame(width: 16)
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Text(item.label)
                    .font(.jakarta(DS.T.navItem, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Spacer()
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

private struct SchnellkasseBanner: View {
    var body: some View {
        Button {
            // TODO: SchnellkasseView (Phase 1)
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schnellkasse")
                        .font(.jakarta(DS.T.quickLabel, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Ohne Tisch kassieren")
                        .font(.jakarta(DS.T.quickSub, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(DS.C.acc)
            .cornerRadius(DS.R.quickBanner)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

private struct SidebarKPIs: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var tableStore:   TableStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KPIBlock(
                label: "TISCHE BESETZT",
                value: "\(tableStore.occupiedCount) / \(tableStore.tables.count)"
            )
            KPIBlock(
                label: "SCHICHT",
                value: sessionStore.hasOpenSession ? "Offen" : "Keine",
                accent: sessionStore.hasOpenSession
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .top
        )
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
    @Environment(\.colorScheme) private var colorScheme

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
    let selectedNav: NavItem
    let onTableTap: (Int, String) -> Void

    var body: some View {
        Group {
            switch selectedNav {
            case .tische:
                TableGridContent(onTableTap: onTableTap)
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

private struct ComingSoonContent: View {
    let nav: NavItem

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(DS.C.text2)
            Text(nav.label)
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text("Wird in Kürze verfügbar sein.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.bg)
    }
}

// MARK: - Tischgitter

private struct TableGridContent: View {
    @EnvironmentObject var tableStore: TableStore
    @EnvironmentObject var sessionStore: SessionStore
    let onTableTap: (Int, String) -> Void

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
                            TableCard(table: table) {
                                onTableTap(table.id, table.name)
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await tableStore.loadTables() }
            }
        }
        .background(DS.C.bg)
    }
}

private struct NoSessionBanner: View {
    @EnvironmentObject var sessionStore: SessionStore
    // Referenz nach oben über Binding nicht möglich hier — Nutzer soll in
    // Kassensitzung-Tab navigieren. Stattdessen: einfacher Hinweis.

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
            Text("Keine offene Kassensitzung — Bestellungen können erst nach Schichteröffnung erstellt werden.")
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
    let table: TableItem
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isOccupied: Bool { table.openOrdersCount > 0 }

    private var bgColor: Color { isOccupied ? DS.C.busyBg : DS.C.sur }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Hintergrund
                bgColor

                // Inhalt
                VStack(alignment: .leading, spacing: 10) {
                    // Zeile 1: Tischname + Badge
                    HStack(alignment: .center, spacing: 8) {
                        Text(table.name)
                            .font(.jakarta(DS.T.tableName, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .lineLimit(1)
                        Spacer()
                        TableStatusBadge(isOccupied: isOccupied)
                    }

                    // Zeile 2: Betrag / Status
                    Text(isOccupied
                         ? "\(table.openOrdersCount) Bestellung\(table.openOrdersCount == 1 ? "" : "en")"
                         : "—")
                        .font(.jakarta(isOccupied ? 16 : DS.T.tableAmount, weight: .semibold))
                        .foregroundColor(isOccupied ? DS.C.busyText : DS.C.text2)
                        .tracking(isOccupied ? 0 : -0.5)

                    // Zeile 3: Meta (mit Trennlinie oben)
                    VStack(spacing: 0) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(DS.C.brd(colorScheme))
                        Spacer().frame(height: 8)
                        HStack(spacing: 6) {
                            if let zoneName = table.zone?.name {
                                Text(zoneName)
                                    .font(.jakarta(DS.T.tableMeta, weight: .regular))
                                    .foregroundColor(DS.C.text2)
                                Circle()
                                    .fill(DS.C.brd(colorScheme))
                                    .frame(width: 4, height: 4)
                            }
                            Text(isOccupied ? "Besetzt" : "Frei")
                                .font(.jakarta(DS.T.tableMeta, weight: .regular))
                                .foregroundColor(isOccupied ? DS.C.busyText : DS.C.freeText)
                        }
                    }
                }
                .padding(14)

                // Linker Akzent-Streifen (nur bei besetzt)
                if isOccupied {
                    Rectangle()
                        .fill(DS.C.stripeBusy)
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
        .frame(minHeight: 120)
    }
}

private struct TableStatusBadge: View {
    let isOccupied: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOccupied ? DS.C.busyText : DS.C.freeText)
                .frame(width: 5, height: 5)
            Text(isOccupied ? "Besetzt" : "Frei")
                .font(.jakarta(DS.T.badge, weight: .semibold))
                .foregroundColor(isOccupied ? DS.C.busyText : DS.C.freeText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isOccupied ? DS.C.busyBg : DS.C.freeBg)
        .cornerRadius(DS.R.badge)
        .fixedSize()
    }
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
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Keine Kassensitzung") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.previewNoSession)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Leer — keine Tische") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    TableOverviewView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(SessionStore.preview)
        .environmentObject(OrderStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

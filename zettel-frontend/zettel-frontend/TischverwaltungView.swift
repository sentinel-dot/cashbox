// TischverwaltungView.swift
// cashbox — Tische & Zonen verwalten (Einstellungen-Tab)

import SwiftUI

// MARK: - Root

struct TischverwaltungView: View {
    @EnvironmentObject var tableStore:    TableStore
    @EnvironmentObject var authStore:     AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @State private var showZoneSheet  = false
    @State private var showTischSheet = false
    @State private var deletingTable: TableItem?
    @State private var showDeleteConfirm = false
    @State private var error:     AppError?
    @State private var showError  = false

    private var canManage: Bool {
        authStore.currentUser?.role == .owner || authStore.currentUser?.role == .manager
    }

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isOnline {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text("\(tableStore.tables.count) Tische · \(tableStore.zones.count) Zonen")
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)

                Spacer()

                if canManage {
                    Button {
                        showZoneSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Zone")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                        }
                        .foregroundColor(DS.C.acc)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                    }
                    .background(DS.C.acc.opacity(0.12))
                    .cornerRadius(DS.R.button)
                    .buttonStyle(.plain)

                    Button {
                        showTischSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Tisch")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                    }
                    .background(DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // ── Content ───────────────────────────────────────────────────
            if tableStore.isLoading {
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {

                            // Zonen
                            if !tableStore.zones.isEmpty {
                                TVSection("ZONEN (\(tableStore.zones.count))") {
                                    ForEach(tableStore.zones) { zone in
                                        let count = tableStore.tables.filter { $0.zone?.id == zone.id }.count
                                        ZoneRow(zone: zone, tableCount: count, colorScheme: colorScheme)
                                    }
                                }
                            }

                            // Tische
                            TVSection("TISCHE (\(tableStore.tables.count))") {
                                if tableStore.tables.isEmpty {
                                    Text("Noch keine Tische angelegt.")
                                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                                        .foregroundColor(DS.C.text2)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(tableStore.tables) { table in
                                        TischRow(
                                            table:     table,
                                            canDelete: canManage,
                                            onDelete: {
                                                deletingTable = table
                                                showDeleteConfirm = true
                                            },
                                            colorScheme: colorScheme
                                        )
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: 560)

                    Spacer()
                }
            }
        }
        .background(DS.C.bg)
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        // ── Zone-Sheet ────────────────────────────────────────────────────
        .sheet(isPresented: $showZoneSheet) {
            ZoneFormSheet { name in
                Task {
                    do {
                        try await tableStore.createZone(name: name)
                        showZoneSheet = false
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        // ── Tisch-Sheet ───────────────────────────────────────────────────
        .sheet(isPresented: $showTischSheet) {
            TischFormSheet(zones: tableStore.zones) { name, zoneId in
                Task {
                    do {
                        try await tableStore.createTable(name: name, zoneId: zoneId)
                        showTischSheet = false
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        // ── Löschen bestätigen ────────────────────────────────────────────
        .confirmationDialog(
            "Tisch deaktivieren?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Deaktivieren", role: .destructive) {
                guard let t = deletingTable else { return }
                Task {
                    do { try await tableStore.deleteTable(id: t.id) }
                    catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Tisch wird deaktiviert und ist nicht mehr buchbar. Aktive Bestellungen bleiben erhalten.")
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
        .task { await tableStore.loadTables() }
    }
}

// MARK: - Section

private struct TVSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

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
            VStack(spacing: 8) { content }
        }
    }
}

// MARK: - ZoneRow

private struct ZoneRow: View {
    let zone:       TableZone
    let tableCount: Int
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 15))
                .foregroundColor(DS.C.acc)
                .frame(width: 32, height: 32)
                .background(DS.C.accBg)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("\(tableCount) Tische")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
        }
        .padding(12)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - TischRow

private struct TischRow: View {
    let table:       TableItem
    let canDelete:   Bool
    let onDelete:    () -> Void
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chair")
                .font(.system(size: 14))
                .foregroundColor(DS.C.text2)
                .frame(width: 32, height: 32)
                .background(DS.C.sur2)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                if let zone = table.zone {
                    Text(zone.name)
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }

            Spacer()

            // Offene Bestellungen
            if table.openOrdersCount > 0 {
                Text("\(table.openOrdersCount) offen")
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(Color(hex: "e67e22"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "e67e22").opacity(0.12))
                    .cornerRadius(6)
            }

            // Aktiv-Badge
            Text(table.isActive ? "Aktiv" : "Inaktiv")
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(table.isActive ? Color(hex: "27ae60") : DS.C.text2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((table.isActive ? Color(hex: "27ae60") : DS.C.text2).opacity(0.12))
                .cornerRadius(6)

            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "e74c3c"))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "e74c3c").opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(table.openOrdersCount > 0)
                .opacity(table.openOrdersCount > 0 ? 0.4 : 1.0)
            }
        }
        .padding(12)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - ZoneFormSheet

private struct ZoneFormSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 16) {
                Text("Neue Zone")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Zonenname")
                        .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder:  "z.B. Terrasse, Bar, Innen …",
                        text:         $name,
                        uiFont:       UIFont.systemFont(ofSize: 14),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $focused
                    )
                    .padding(.horizontal, 12)
                    .frame(height: DS.S.inputHeight)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(focused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused)
                }

                HStack(spacing: 10) {
                    Button("Abbrechen") { dismiss() }
                        .font(.jakarta(DS.T.loginButton, weight: .medium))
                        .foregroundColor(DS.C.text2)
                        .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.button)
                        .buttonStyle(.plain)

                    Button {
                        onSave(name.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text("Speichern")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                    }
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? DS.C.acc.opacity(0.4) : DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(DS.C.sur)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
        .onAppear { focused = true }
    }
}

// MARK: - TischFormSheet

private struct TischFormSheet: View {
    let zones:  [TableZone]
    let onSave: (String, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name           = ""
    @State private var selectedZoneId: Int? = nil
    @State private var focused        = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 16) {
                Text("Neuer Tisch")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .padding(.top, 8)

                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tischname")
                        .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder:  "z.B. T1, Bar 3, Lounge 2 …",
                        text:         $name,
                        uiFont:       UIFont.systemFont(ofSize: 14),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $focused
                    )
                    .padding(.horizontal, 12)
                    .frame(height: DS.S.inputHeight)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(focused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused)
                }

                // Zone-Picker
                if !zones.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zone (optional)")
                            .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ZonePill(label: "Keine Zone", isActive: selectedZoneId == nil) {
                                    selectedZoneId = nil
                                }
                                ForEach(zones) { zone in
                                    ZonePill(label: zone.name, isActive: selectedZoneId == zone.id) {
                                        selectedZoneId = zone.id
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Abbrechen") { dismiss() }
                        .font(.jakarta(DS.T.loginButton, weight: .medium))
                        .foregroundColor(DS.C.text2)
                        .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.button)
                        .buttonStyle(.plain)

                    Button {
                        onSave(name.trimmingCharacters(in: .whitespaces), selectedZoneId)
                    } label: {
                        Text("Speichern")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                    }
                    .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? DS.C.acc.opacity(0.4) : DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { focused = true }
    }
}

private struct ZonePill: View {
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text2)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isActive ? DS.C.acc : DS.C.sur2)
                .cornerRadius(DS.R.button)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}

// MARK: - Previews

#Preview("Tischverwaltung") {
    TischverwaltungView()
        .environmentObject(TableStore.preview)
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Leer") {
    TischverwaltungView()
        .environmentObject(TableStore.previewEmpty)
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    TischverwaltungView()
        .environmentObject(TableStore.preview)
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

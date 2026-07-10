// TischverwaltungView.swift
// cashbox — Tische & Zonen verwalten (Einstellungen-Tab)
// Design v3: DS-Tokens statt Hardcode-Hex, 44pt-Aktionen.

import SwiftUI

// MARK: - Root

struct TischverwaltungView: View {
    @EnvironmentObject var tableStore:    TableStore
    @EnvironmentObject var authStore:     AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

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

            // Header
            HStack(spacing: 10) {
                Text("\(tableStore.tables.count) Tische · \(tableStore.zones.count) Zonen")
                    .font(DS.F.bodyBold)
                    .monospacedDigit()
                    .foregroundColor(DS.C.text)

                Spacer()

                if canManage {
                    Button {
                        showZoneSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Zone")
                        }
                    }
                    .buttonStyle(DSSecondaryButton(height: 42, fullWidth: false))

                    Button {
                        showTischSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Tisch")
                        }
                    }
                    .buttonStyle(DSPrimaryButton(height: 42, fullWidth: false))
                }
            }
            .padding(.horizontal, DS.S.pagePad)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)

            // Content
            if tableStore.isLoading {
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {

                            if !tableStore.zones.isEmpty {
                                TVSection("Zonen (\(tableStore.zones.count))") {
                                    ForEach(tableStore.zones) { zone in
                                        let count = tableStore.tables.filter { $0.zone?.id == zone.id }.count
                                        ZoneRow(zone: zone, tableCount: count)
                                    }
                                }
                            }

                            TVSection("Tische (\(tableStore.tables.count))") {
                                if tableStore.tables.isEmpty {
                                    Text("Noch keine Tische angelegt.")
                                        .font(DS.F.sub)
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
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(DS.S.pagePad)
                    }
                    .frame(maxWidth: 600)

                    Spacer()
                }
            }
        }
        .background(DS.C.bg)
        .animation(DS.M.base, value: networkMonitor.isOnline)
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
            DSSectionLabel(text: title)
            VStack(spacing: 8) { content }
        }
    }
}

// MARK: - ZoneRow

private struct ZoneRow: View {
    let zone:       TableZone
    let tableCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 16))
                .foregroundColor(DS.C.accT)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.accBg))

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("\(tableCount) Tisch\(tableCount == 1 ? "" : "e")")
                    .font(DS.F.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
        }
        .padding(14)
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

// MARK: - TischRow

private struct TischRow: View {
    let table:       TableItem
    let canDelete:   Bool
    let onDelete:    () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chair")
                .font(.system(size: 15))
                .foregroundColor(DS.C.text2)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.sur2))

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.C.text)
                if let zone = table.zone {
                    Text(zone.name)
                        .font(DS.F.caption)
                        .foregroundColor(DS.C.text2)
                }
            }

            Spacer()

            if table.openOrdersCount > 0 {
                DSPill(
                    label: "\(table.openOrdersCount) offen",
                    fg: DS.C.brassText,
                    bg: DS.C.brassBg
                )
            }

            DSPill(
                label: table.isActive ? "Aktiv" : "Inaktiv",
                fg: table.isActive ? DS.C.accT : DS.C.text2,
                bg: table.isActive ? DS.C.accBg : DS.C.sur2
            )

            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.C.dangerText)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.dangerBg.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(table.openOrdersCount > 0)
                .opacity(table.openOrdersCount > 0 ? 0.4 : 1.0)
            }
        }
        .padding(14)
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

// MARK: - ZoneFormSheet

private struct ZoneFormSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
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

            VStack(alignment: .leading, spacing: 18) {
                Text("Neue Zone")
                    .font(DS.F.title)
                    .foregroundColor(DS.C.text)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Zonenname")
                    NoAssistantTextField(
                        placeholder:  "z.B. Terrasse, Bar, Innen …",
                        text:         $name,
                        uiFont:       UIFont.systemFont(ofSize: 16),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $focused
                    )
                    .padding(.horizontal, 14)
                    .frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(focused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: focused ? 1.5 : 1)
                    )
                    .animation(DS.M.fast, value: focused)
                }

                HStack(spacing: 10) {
                    Button("Abbrechen") { dismiss() }
                        .buttonStyle(DSSecondaryButton())

                    Button {
                        onSave(name.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text("Speichern")
                    }
                    .buttonStyle(DSPrimaryButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(DS.S.pagePad)
        }
        .background(DS.C.sur)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
        .onAppear { focused = true }
    }
}

// MARK: - TischFormSheet

private struct TischFormSheet: View {
    let zones:  [TableZone]
    let onSave: (String, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
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

            VStack(alignment: .leading, spacing: 18) {
                Text("Neuer Tisch")
                    .font(DS.F.title)
                    .foregroundColor(DS.C.text)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Tischname")
                    NoAssistantTextField(
                        placeholder:  "z.B. T1, Bar 3, Lounge 2 …",
                        text:         $name,
                        uiFont:       UIFont.systemFont(ofSize: 16),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $focused
                    )
                    .padding(.horizontal, 14)
                    .frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(focused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: focused ? 1.5 : 1)
                    )
                    .animation(DS.M.fast, value: focused)
                }

                if !zones.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DSSectionLabel(text: "Zone (optional)")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                TZonePill(label: "Keine Zone", isActive: selectedZoneId == nil) {
                                    selectedZoneId = nil
                                }
                                ForEach(zones) { zone in
                                    TZonePill(label: zone.name, isActive: selectedZoneId == zone.id) {
                                        selectedZoneId = zone.id
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Abbrechen") { dismiss() }
                        .buttonStyle(DSSecondaryButton())

                    Button {
                        onSave(name.trimmingCharacters(in: .whitespaces), selectedZoneId)
                    } label: {
                        Text("Speichern")
                    }
                    .buttonStyle(DSPrimaryButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(DS.S.pagePad)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { focused = true }
    }
}

private struct TZonePill: View {
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(isActive ? DS.C.acc : DS.C.sur2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isActive)
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

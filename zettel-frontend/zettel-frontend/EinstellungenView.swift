// EinstellungenView.swift
// cashbox — Einstellungen: Sub-Nav + Betrieb/Benutzer/Geräte/Kasse/TSE/Abo nach Referenz-Design

import SwiftUI

// MARK: - Tab Enum

fileprivate enum ETab: String, Hashable, CaseIterable {
    case betriebsdaten = "Betriebsdaten"
    case benutzer      = "Benutzer"
    case geraete       = "Geräte"
    case kassensystem  = "Kassensystem"
    case tische        = "Tische & Zonen"
    case tse           = "TSE / Fiskaly"
    case abonnement    = "Abonnement"
    case datenschutz   = "Datenschutz"

    var icon: String {
        switch self {
        case .betriebsdaten: return "building.2"
        case .benutzer:      return "person.2"
        case .geraete:       return "ipad"
        case .kassensystem:  return "tablecells"
        case .tische:        return "square.grid.2x2"
        case .tse:           return "star.circle"
        case .abonnement:    return "creditcard"
        case .datenschutz:   return "shield"
        }
    }

    static let sections: [(String, [ETab])] = [
        ("Allgemein", [.betriebsdaten, .benutzer, .geraete]),
        ("Kasse",     [.kassensystem, .tische, .tse]),
        ("Abonnement",[.abonnement, .datenschutz])
    ]
}

// MARK: - Root

struct EinstellungenView: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var usersStore:     UsersStore
    @EnvironmentObject var tableStore:     TableStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var activeTab = ETab.betriebsdaten

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ETopBar()
                HStack(spacing: 0) {
                    ESettingsNav(activeTab: $activeTab)
                    Rectangle().fill(DS.C.brdLight).frame(width: 1)
                    ESettingsMain(activeTab: $activeTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }
}

// MARK: - Top Bar

private struct ETopBar: View {
    var body: some View {
        HStack {
            Text("Einstellungen")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Settings Sub-Nav

private struct ESettingsNav: View {
    @Binding var activeTab: ETab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ETab.sections, id: \.0) { section, tabs in
                        Text(section.uppercased())
                            .font(.jakarta(9, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .tracking(0.8)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(tabs, id: \.self) { tab in
                            ENavItem(
                                tab:      tab,
                                isActive: activeTab == tab,
                                onTap:    { activeTab = tab }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 200)
        .background(DS.C.bg)
    }
}

private struct ENavItem: View {
    let tab:      ETab
    let isActive: Bool
    let onTap:    () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(tab.rawValue)
                    .font(.jakarta(12, weight: isActive ? .semibold : .medium))
                Spacer()
            }
            .foregroundColor(isActive ? DS.C.text : (hovered ? DS.C.text : DS.C.text2))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? DS.C.sur : Color.clear)
            .overlay(
                Rectangle()
                    .frame(width: isActive ? 2 : 0)
                    .foregroundColor(DS.C.acc),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

// MARK: - Settings Main (content area)

private struct ESettingsMain: View {
    @Binding var activeTab: ETab

    var body: some View {
        ZStack {
            DS.C.bg.ignoresSafeArea()
            switch activeTab {
            case .betriebsdaten: EBetriebsdatenTab()
            case .benutzer:      EBenutzerTab()
            case .geraete:       EGeraeteTab()
            case .kassensystem:  EKassensystemTab()
            case .tische:        TischverwaltungView()
            case .tse:           ETSETab()
            case .abonnement:    EAbonnementTab()
            case .datenschutz:   EDatenschutzTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Betriebsdaten Tab

private struct EBetriebsdatenTab: View {
    @EnvironmentObject var authStore: AuthStore
    private let api = APIClient.shared

    @State private var name       = ""
    @State private var address    = ""
    @State private var vatId      = ""
    @State private var taxNumber  = ""
    @State private var isSaving   = false
    @State private var showSaved  = false
    @State private var error:     AppError?
    @State private var showError  = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // Betriebsdaten card
                ESettingsSectionHeader(
                    title: "Betriebsdaten",
                    sub:   "Pflichtfelder für den Bon — müssen mit Ihren steuerlichen Angaben übereinstimmen."
                )
                ECard {
                    EInputRow(
                        label: "Unternehmensname",
                        sub:   "Erscheint auf jedem Bon (§ 14 UStG)",
                        placeholder: "Mein Café GmbH",
                        text: $name
                    )
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    EInputRow(
                        label: "Adresse",
                        sub:   "Vollständige Betriebsadresse",
                        placeholder: "Musterstr. 1, 10115 Berlin",
                        text: $address
                    )
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    EInputRow(
                        label: "Steuernummer",
                        sub:   "Vom Finanzamt zugewiesene Steuernummer",
                        placeholder: "12/345/67890",
                        text: $taxNumber
                    )
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    EInputRow(
                        label: "USt-IdNr.",
                        sub:   "Optional, aber empfohlen (§ 14 UStG)",
                        placeholder: "DE123456789",
                        text: $vatId,
                        showBorder: false
                    )
                }

                // Bon-Einstellungen card
                ESettingsSectionHeader(
                    title: "Bon-Einstellungen",
                    sub:   "Wie Bons angezeigt und verteilt werden."
                )
                ECard {
                    ERow("Bon per E-Mail versenden",
                         sub: "Kunde kann nach Zahlung eine Bon-PDF anfordern") {
                        Text("Phase 5")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.C.sur2).cornerRadius(10)
                    }
                }

                // Save button
                HStack {
                    Spacer()
                    Button {
                        Task { await saveTenant() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                                    .frame(width: 60)
                            } else {
                                Text(showSaved ? "Gespeichert ✓" : "Änderungen speichern")
                                    .font(.jakarta(11, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                    }
                    .background(showSaved ? DS.C.successText : (name.isEmpty || address.isEmpty ? DS.C.acc.opacity(0.4) : DS.C.acc))
                    .cornerRadius(8)
                    .disabled(isSaving || name.isEmpty || address.isEmpty)
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: showSaved)
                }
            }
            .padding(24)
        }
        .task { await loadTenant() }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func loadTenant() async {
        do {
            let t: Tenant = try await api.get("/tenants/me")
            name       = t.name
            address    = t.address
            vatId      = t.vatId      ?? ""
            taxNumber  = t.taxNumber  ?? ""
        } catch let e as AppError {
            error = e; showError = true
        } catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func saveTenant() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = UpdateTenantBody(
                name:      name,
                address:   address,
                vatId:     vatId.isEmpty      ? nil : vatId,
                taxNumber: taxNumber.isEmpty  ? nil : taxNumber
            )
            let _: OkResponse = try await api.patch("/tenants/me", body: body)
            showSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
        } catch let e as AppError {
            error = e; showError = true
        } catch { self.error = .unknown(error.localizedDescription); showError = true }
    }
}

private struct UpdateTenantBody: Encodable {
    let name:      String
    let address:   String
    let vatId:     String?
    let taxNumber: String?
}

// MARK: - Benutzer Tab

private struct EBenutzerTab: View {
    @EnvironmentObject var usersStore: UsersStore
    @EnvironmentObject var authStore:  AuthStore

    @State private var showAddSheet      = false
    @State private var editingUser:      User?
    @State private var deletingUser:     User?
    @State private var showDeleteConfirm = false
    @State private var error:            AppError?
    @State private var showError         = false

    private var canManage: Bool {
        authStore.currentUser?.role == .owner || authStore.currentUser?.role == .manager
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Benutzer",
                    sub:   "Mitarbeiter mit Zugang zum Kassensystem. PIN ermöglicht schnellen Gerätewechsel."
                )

                if usersStore.isLoading {
                    ProgressView().progressViewStyle(.circular).frame(maxWidth: .infinity)
                } else {
                    ECard {
                        ForEach(Array(usersStore.users.enumerated()), id: \.element.id) { idx, user in
                            EUserRow(
                                user:      user,
                                isSelf:    user.id == authStore.currentUser?.id,
                                canManage: canManage,
                                isLast:    idx == usersStore.users.count - 1,
                                onEdit:    { editingUser = user },
                                onDelete:  { deletingUser = user; showDeleteConfirm = true }
                            )
                        }
                    }
                }

                if canManage {
                    HStack {
                        Spacer()
                        Button { showAddSheet = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Benutzer hinzufügen")
                                    .font(.jakarta(11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(DS.C.acc)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .task {
            await usersStore.loadUsers()
            if !usersStore.users.isEmpty { authStore.updatePINUsers(usersStore.users) }
        }
        .sheet(isPresented: $showAddSheet) {
            UserFormSheet(user: nil) { name, email, password, role, pin in
                Task {
                    do {
                        try await usersStore.createUser(name: name, email: email, password: password, role: role, pin: pin)
                        showAddSheet = false
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        .sheet(item: $editingUser) { user in
            UserFormSheet(user: user) { name, _, _, role, pin in
                Task {
                    do {
                        try await usersStore.updateUser(id: user.id, name: name, role: role, pin: pin)
                        editingUser = nil
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        .confirmationDialog("Mitarbeiter deaktivieren?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Deaktivieren", role: .destructive) {
                guard let u = deletingUser else { return }
                Task {
                    do { try await usersStore.deleteUser(id: u.id) }
                    catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Account wird deaktiviert und kann sich nicht mehr einloggen.")
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }
}

private struct EUserRow: View {
    let user:      User
    let isSelf:    Bool
    let canManage: Bool
    let isLast:    Bool
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    private var roleColor: Color {
        switch user.role {
        case .owner:   return DS.C.acc
        case .manager: return DS.C.warnText
        case .staff:   return DS.C.text2
        }
    }

    private var avatarBg: Color {
        switch user.role {
        case .owner:   return DS.C.accBg
        case .manager: return DS.C.warnBg
        case .staff:   return DS.C.sur2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle().fill(avatarBg).frame(width: 34, height: 34)
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(roleColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(user.name)
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Text(user.role.displayName)
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(roleColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(roleColor.opacity(0.12))
                            .cornerRadius(20)
                        if isSelf {
                            Text("Ich")
                                .font(.jakarta(9, weight: .semibold))
                                .foregroundColor(DS.C.accT)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DS.C.accBg)
                                .cornerRadius(4)
                        }
                    }
                    Text("\(user.email) · PIN: ••••")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                if canManage {
                    HStack(spacing: 6) {
                        ESmallBtn(label: "Bearbeiten", danger: false, action: onEdit)
                        if !isSelf {
                            ESmallBtn(label: "Entfernen", danger: true, action: onDelete)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !isLast {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
            }
        }
    }
}

// MARK: - Geräte Tab

private struct EGeraeteTab: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Geräte",
                    sub:   "Jedes Gerät hat einen eigenen Fiskaly TSE-Client. Bei Verlust sofort sperren."
                )
                ECard {
                    ERow("Dieses Gerät", sub: "Aktuell eingeloggt · TSE-Client wird mit Fiskaly aktiviert") {
                        HStack(spacing: 4) {
                            Circle().fill(DS.C.successText).frame(width: 5, height: 5)
                            Text("Online")
                                .font(.jakarta(10, weight: .semibold))
                                .foregroundColor(DS.C.successText)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(DS.C.successBg).cornerRadius(20)
                    }
                }
                ECard {
                    ERow("Weitere Geräte verwalten",
                         sub: "Geräteregistrierung und TSE-Client-Verwaltung über das Admin-Panel") {
                        Text("Phase 5")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.C.sur2).cornerRadius(10)
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Kassensystem Tab

private struct EKassensystemTab: View {
    @AppStorage("setting_tische_verwenden")     private var tischeVerwenden    = true
    @AppStorage("setting_schicht_erinnerung")   private var schichtErinnerung  = true
    @AppStorage("setting_stornobegruendung")    private var stornoBegruendung  = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Kassensystem",
                    sub:   "Betriebsverhalten und Pflicht-Einstellungen."
                )
                ECard {
                    ERow("Tische verwenden",
                         sub: "Deaktivieren für reinen Schnellkassenbetrieb (z. B. Späti)") {
                        EToggle(isOn: $tischeVerwenden)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Tägliche Schicht-Erinnerung",
                         sub: "Warnung wenn Sitzung länger als 24 Stunden offen (GoBD)") {
                        EToggle(isOn: $schichtErinnerung)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Stornobegründung erzwingen",
                         sub: "Storno ohne Pflichtfeld-Begründung nicht möglich") {
                        EToggle(isOn: $stornoBegruendung)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Mindest-App-Version",
                         sub: "Ältere App-Versionen werden blockiert (426)") {
                        Text("1.0.0")
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - TSE / Fiskaly Tab

private struct ETSETab: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "TSE / Fiskaly",
                    sub:   "Technische Signatureinheit — gesetzlich vorgeschrieben (KassenSichV)."
                )
                ECard {
                    ERow("TSS-Status", sub: "Fiskaly Cloud-TSE") {
                        HStack(spacing: 4) {
                            Circle().fill(DS.C.warnText).frame(width: 5, height: 5)
                            Text("Phase 1 — ausstehend")
                                .font(.jakarta(10, weight: .semibold))
                                .foregroundColor(DS.C.warnText)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(DS.C.warnBg).cornerRadius(20)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("TSS-ID", sub: "Wird nach Fiskaly-Aktivierung vergeben") {
                        Text("—")
                            .font(.jakarta(12, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Offline-Betrieb",
                         sub: "Transaktionen werden lokal gespeichert und bei Reconnect signiert") {
                        Text("Phase 3")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.C.sur2).cornerRadius(10)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("ELSTER-Meldung",
                         sub: "Kasse beim Finanzamt melden (einmalig, nach Fiskaly-Aktivierung)") {
                        Text("Phase 2")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.C.sur2).cornerRadius(10)
                    }
                }

                // Info box
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(DS.C.accT)
                        .padding(.top, 1)
                    Text("TSE-Aktivierung erfolgt vor dem Go-Live. Phase 1 (Pilot-Betrieb) ist gesetzlich zulässig, muss aber vor dem regulären Betrieb umgestellt werden.")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.accT)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(DS.C.accBg)
                .cornerRadius(10)
            }
            .padding(24)
        }
    }
}

// MARK: - Abonnement Tab

private struct EAbonnementTab: View {
    private let api = APIClient.shared
    @State private var tenant:   Tenant?
    @State private var isLoading = false

    private var planLabel: String {
        switch tenant?.plan {
        case .starter:  return "Starter Plan"
        case .pro:      return "Pro Plan"
        case .business: return "Business Plan"
        case nil:       return "—"
        }
    }

    private var statusLabel: String {
        switch tenant?.subscriptionStatus {
        case .trial:     return "Trial"
        case .active:    return "Aktiv"
        case .pastDue:   return "Zahlung ausstehend"
        case .cancelled: return "Gekündigt"
        case nil:        return "—"
        }
    }

    private var statusColor: Color {
        switch tenant?.subscriptionStatus {
        case .active:    return DS.C.successText
        case .trial:     return DS.C.warnText
        case .pastDue:   return DS.C.dangerText
        case .cancelled: return DS.C.text2
        case nil:        return DS.C.text2
        }
    }

    private var reportDays: String {
        switch tenant?.plan {
        case .starter:  return "30 Tage"
        case .pro:      return "365 Tage"
        case .business: return "10 Jahre"
        case nil:       return "—"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Abonnement",
                    sub:   "Ihr aktueller Plan und Abrechnungsdetails."
                )

                if isLoading {
                    ProgressView().progressViewStyle(.circular).frame(maxWidth: .infinity)
                } else {
                    // Plan highlight
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(planLabel)
                                    .font(.jakarta(15, weight: .semibold))
                                    .foregroundColor(DS.C.accT)
                                Text(statusLabel)
                                    .font(.jakarta(11, weight: .semibold))
                                    .foregroundColor(statusColor)
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(statusColor.opacity(0.12)).cornerRadius(20)
                            }
                            if tenant?.subscriptionStatus == .trial {
                                Text("14-Tage-Testphase läuft")
                                    .font(.jakarta(11, weight: .regular))
                                    .foregroundColor(DS.C.accT.opacity(0.7))
                            }
                        }
                        Spacer()
                        if tenant?.plan == .starter || tenant?.subscriptionStatus == .trial {
                            Button {
                                // Stripe upgrade — Phase 3
                            } label: {
                                Text("Auf Pro upgraden")
                                    .font(.jakarta(11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(DS.C.acc)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(DS.C.accBg)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(DS.C.acc.opacity(0.15), lineWidth: 1)
                    )

                    // Plan limits
                    ECard {
                        ERow("Geräte", sub: "Starter: max. 1 Gerät") {
                            Text("1 / 1")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        Rectangle().fill(DS.C.brdLight).frame(height: 1)
                        ERow("Berichts-Zeitraum", sub: "Verfügbare Historien-Tiefe") {
                            Text(reportDays)
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        Rectangle().fill(DS.C.brdLight).frame(height: 1)
                        ERow("Stripe-Kundennummer", sub: "Für Rechnungen und Zahlungsmethoden") {
                            Button {
                                // Stripe portal — Phase 3
                            } label: {
                                Text("Stripe-Portal öffnen →")
                                    .font(.jakarta(12, weight: .semibold))
                                    .foregroundColor(DS.C.accT)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Gefahrenzone
                ESettingsSectionHeader(
                    title: "Gefahrenzone",
                    sub:   "Irreversible Aktionen — mit Bedacht verwenden."
                )
                ECard {
                    ERow("Abonnement kündigen",
                         sub: "Zugang endet zum Periodenende. Daten werden 10 Jahre aufbewahrt (GoBD).") {
                        ESmallBtn(label: "Kündigen", danger: true) {
                            // Cancel — Phase 3
                        }
                    }
                }
            }
            .padding(24)
        }
        .task { await loadTenant() }
    }

    private func loadTenant() async {
        isLoading = true
        defer { isLoading = false }
        do { tenant = try await api.get("/tenants/me") }
        catch { /* ignore silently */ }
    }
}

// MARK: - Datenschutz Tab

private struct EDatenschutzTab: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Datenschutz & Rechtliches",
                    sub:   "Ihre Pflichten als Kassenbetreiber und Datenschutzeinstellungen."
                )
                ECard {
                    ERow("AVV unterzeichnet",
                         sub: "Auftragsverarbeitungsvertrag (DSGVO-Pflicht)") {
                        HStack(spacing: 8) {
                            Text("✓ Erstellt")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.successText)
                            ESmallBtn(label: "Herunterladen", danger: false) {}
                        }
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Verfahrensdokumentation",
                         sub: "Pflicht vor produktivem Einsatz (GoBD)") {
                        HStack(spacing: 8) {
                            Text("✓ Erstellt")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.successText)
                            ESmallBtn(label: "PDF herunterladen", danger: false) {}
                        }
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Datenspeicherung",
                         sub: "Hetzner Frankfurt · DSGVO-konform") {
                        Text("EU · DE")
                            .font(.jakarta(12, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    ERow("Daten exportieren",
                         sub: "ZIP-Export aller Betriebsdaten (30 Tage nach Kündigung)") {
                        ESmallBtn(label: "Export anfordern", danger: false) {}
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Shared Layout Components

private struct ESettingsSectionHeader: View {
    let title: String
    let sub:   String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.jakarta(14, weight: .semibold))
                .foregroundColor(DS.C.text)
                .tracking(-0.2)
            Text(sub)
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ECard<C: View>: View {
    @ViewBuilder let content: C
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

private struct ERow<R: View>: View {
    let label: String
    var sub:   String? = nil
    @ViewBuilder let right: R

    init(_ label: String, sub: String? = nil, @ViewBuilder right: () -> R) {
        self.label = label
        self.sub   = sub
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.jakarta(13, weight: .medium))
                    .foregroundColor(DS.C.text)
                if let s = sub {
                    Text(s)
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            right
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct EInputRow: View {
    let label:       String
    var sub:         String? = nil
    let placeholder: String
    @Binding var text: String
    var showBorder: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.jakarta(13, weight: .medium))
                        .foregroundColor(DS.C.text)
                    if let s = sub {
                        Text(s)
                            .font(.jakarta(11, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NoAssistantTextField(
                    placeholder: placeholder,
                    text:        $text,
                    uiFont:      UIFont.systemFont(ofSize: 12),
                    uiTextColor: UIColor(DS.C.text),
                    isFocused:   $isFocused
                )
                .frame(height: 34)
                .frame(minWidth: 180, maxWidth: 220)
                .padding(.horizontal, 12)
                .background(DS.C.bg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showBorder {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
            }
        }
    }
}

private struct EToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isOn ? DS.C.acc : DS.C.sur2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(isOn ? Color.clear : DS.C.brdLight, lineWidth: 1)
                    )
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

private struct ESmallBtn: View {
    let label:  String
    let danger: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.jakarta(11, weight: .semibold))
                .foregroundColor(danger ? DS.C.dangerText : DS.C.text2)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    danger && hovered ? DS.C.dangerBg :
                    (!danger && hovered ? DS.C.sur2 : Color.clear)
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            danger ? DS.C.dangerText.opacity(0.5) : DS.C.brdLight,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}

// MARK: - User Form Sheet (unchanged)

private struct UserFormSheet: View {
    let user:   User?
    let onSave: (String, String, String, UserRole, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var role     = UserRole.staff
    @State private var pin      = ""

    var isEdit:  Bool { user != nil }
    var canSave: Bool { !name.isEmpty && (isEdit || (!email.isEmpty && !password.isEmpty)) }

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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isEdit ? "Mitarbeiter bearbeiten" : "Neuer Mitarbeiter")
                        .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .padding(.top, 8)

                    UFormField(label: "Name", placeholder: "Vollständiger Name", text: $name)

                    if !isEdit {
                        UFormField(label: "E-Mail", placeholder: "mitarbeiter@example.com", text: $email,
                                   keyboardType: .emailAddress, autocapitalizationType: .none)
                        UFormField(label: "Passwort", placeholder: "Mindestens 8 Zeichen", text: $password, isSecure: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rolle")
                            .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                        HStack(spacing: 8) {
                            ForEach([UserRole.staff, .manager, .owner], id: \.self) { r in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.1)) { role = r }
                                } label: {
                                    Text(r.displayName)
                                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                        .foregroundColor(role == r ? .white : DS.C.text2)
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(role == r ? DS.C.acc : DS.C.sur2)
                                        .cornerRadius(DS.R.button)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    UFormField(label: "PIN (4 Stellen, optional)", placeholder: "1234", text: $pin,
                               keyboardType: .numberPad, autocapitalizationType: .none)
                        .keyboardType(.numberPad)

                    HStack(spacing: 10) {
                        Button("Abbrechen") { dismiss() }
                            .font(.jakarta(DS.T.loginButton, weight: .medium))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.button)
                            .buttonStyle(.plain)

                        Button {
                            onSave(name, email, password, role, pin.isEmpty ? nil : pin)
                        } label: {
                            Text("Speichern")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        }
                        .background(canSave ? DS.C.acc : DS.C.acc.opacity(0.4))
                        .cornerRadius(DS.R.button)
                        .disabled(!canSave)
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            if let u = user { name = u.name; role = u.role }
        }
    }
}

private struct UFormField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var isSecure:               Bool                          = false
    var keyboardType:           UIKeyboardType                = .default
    var autocapitalizationType: UITextAutocapitalizationType  = .words
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(DS.C.text2)
            NoAssistantTextField(
                placeholder:            placeholder,
                text:                   $text,
                keyboardType:           keyboardType,
                uiFont:                 UIFont.systemFont(ofSize: 14),
                uiTextColor:            UIColor(DS.C.text),
                isSecure:               isSecure,
                autocapitalizationType: autocapitalizationType,
                isFocused:              $isFocused
            )
            .padding(.horizontal, 12)
            .frame(height: DS.S.inputHeight)
            .background(DS.C.bg)
            .cornerRadius(DS.R.input)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(isFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }
}

// MARK: - Previews

#Preview("Betriebsdaten") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Benutzer") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

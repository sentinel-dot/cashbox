// EinstellungenView.swift
// cashbox — Einstellungen: Sub-Nav + Betrieb/Benutzer/Geräte/Kasse/TSE/Abo
// Design v3: native Controls (Toggle), keine Seitenstreifen/Hover, DS-Komponenten.

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
                        .dsBannerTransition()
                }
                ETopBar()
                HStack(spacing: 0) {
                    ESettingsNav(activeTab: $activeTab)
                    Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)
                    ESettingsMain(activeTab: $activeTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
    }
}

// MARK: - Top Bar

private struct ETopBar: View {
    var body: some View {
        HStack {
            Text("Einstellungen")
                .dsFont(.heading)
                .foregroundColor(DS.C.text)
            Spacer()
        }
        .padding(.horizontal, DS.S.pagePad)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ETab.sections, id: \.0) { section, tabs in
                        DSSectionLabel(text: section)
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                        ForEach(tabs, id: \.self) { tab in
                            ENavItem(
                                tab:      tab,
                                isActive: activeTab == tab,
                                onTap:    { withAnimation(DS.M.fast) { activeTab = tab } }
                            )
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 230)
        .background(DS.C.sur)
    }
}

private struct ENavItem: View {
    let tab:      ETab
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .dsFont(.raw(15, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? DS.C.accT : DS.C.text2)
                    .frame(width: 22)
                Text(tab.rawValue)
                    .dsFont(.raw(15, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? DS.C.accT : DS.C.text2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .fill(isActive ? DS.C.accBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isActive)
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
                ESettingsSectionHeader(
                    title: "Betriebsdaten",
                    sub:   "Pflichtfelder für den Bon — müssen mit deinen steuerlichen Angaben übereinstimmen."
                )
                ECard {
                    EInputRow(
                        label: "Unternehmensname",
                        sub:   "Erscheint auf jedem Bon (§ 14 UStG)",
                        placeholder: "Mein Café GmbH",
                        text: $name
                    )
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    EInputRow(
                        label: "Adresse",
                        sub:   "Vollständige Betriebsadresse",
                        placeholder: "Musterstr. 1, 10115 Berlin",
                        text: $address
                    )
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    EInputRow(
                        label: "Steuernummer",
                        sub:   "Vom Finanzamt zugewiesene Steuernummer",
                        placeholder: "12/345/67890",
                        text: $taxNumber
                    )
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    EInputRow(
                        label: "USt-IdNr.",
                        sub:   "Optional, aber empfohlen (§ 14 UStG)",
                        placeholder: "DE123456789",
                        text: $vatId,
                        showBorder: false
                    )
                }

                ESettingsSectionHeader(
                    title: "Bon-Einstellungen",
                    sub:   "Wie Bons angezeigt und verteilt werden."
                )
                ECard {
                    ERow("Bon per E-Mail versenden",
                         sub: "Kunde kann nach Zahlung eine Bon-PDF anfordern") {
                        DSPill(label: "Bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await saveTenant() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(showSaved ? "Gespeichert ✓" : "Änderungen speichern")
                            }
                        }
                    }
                    .buttonStyle(DSPrimaryButton(height: 46, fullWidth: false))
                    .disabled(isSaving || name.isEmpty || address.isEmpty)
                    .animation(DS.M.base, value: showSaved)
                }
            }
            .padding(DS.S.pagePad)
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
                HStack(alignment: .top) {
                    ESettingsSectionHeader(
                        title: "Benutzer",
                        sub:   "Mitarbeiter mit Zugang zum Kassensystem. PIN ermöglicht schnellen Gerätewechsel."
                    )
                    Spacer()
                    if canManage {
                        Button { showAddSheet = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .dsFont(.raw(13, weight: .bold))
                                Text("Benutzer hinzufügen")
                            }
                        }
                        .buttonStyle(DSPrimaryButton(height: 42, fullWidth: false))
                    }
                }

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
            }
            .padding(DS.S.pagePad)
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
        case .owner:   return DS.C.accT
        case .manager: return DS.C.brassText
        case .staff:   return DS.C.text2
        }
    }

    private var roleBg: Color {
        switch user.role {
        case .owner:   return DS.C.accBg
        case .manager: return DS.C.brassBg
        case .staff:   return DS.C.sur2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(roleBg).frame(width: 40, height: 40)
                    Text(String(user.name.prefix(1)).uppercased())
                        .dsFont(.raw(15, weight: .semibold))
                        .foregroundColor(roleColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(user.name)
                            .dsFont(.raw(16, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        DSPill(label: user.role.displayName, fg: roleColor, bg: roleBg, showDot: false)
                        if isSelf {
                            Text("Ich")
                                .dsFont(.label)
                                .foregroundColor(DS.C.accT)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(DS.C.accBg))
                        }
                    }
                    Text("\(user.email) · PIN: ••••")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                if canManage {
                    HStack(spacing: 8) {
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
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    .padding(.leading, 70)
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
                        DSPill(label: "Online", fg: DS.C.successText, bg: DS.C.successBg)
                    }
                }
                ECard {
                    ERow("Weitere Geräte verwalten",
                         sub: "Geräteregistrierung und TSE-Client-Verwaltung über das Admin-Panel") {
                        DSPill(label: "Bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
                    }
                }
            }
            .padding(DS.S.pagePad)
        }
    }
}

// MARK: - Kassensystem Tab

private struct EKassensystemTab: View {
    @AppStorage("setting_tische_verwenden")     private var tischeVerwenden    = true
    @AppStorage("setting_schicht_erinnerung")   private var schichtErinnerung  = true
    @AppStorage("setting_stornobegruendung")    private var stornoBegruendung  = true
    @AppStorage(DSAppearance.storageKey)        private var appearanceRaw      = DSAppearance.system.rawValue

    private var appearanceBinding: Binding<DSAppearance> {
        Binding(
            get: { DSAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ESettingsSectionHeader(
                    title: "Kassensystem",
                    sub:   "Betriebsverhalten und Pflicht-Einstellungen."
                )
                ECard {
                    ERow("Darstellung",
                         sub: "System folgt der iPad-Einstellung") {
                        DSSegmentedControl(
                            selection: appearanceBinding,
                            options: DSAppearance.allCases.map { (value: $0, label: $0.label) }
                        )
                        .frame(width: 300)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Tische verwenden",
                         sub: "Deaktivieren für reinen Schnellkassenbetrieb (z. B. Späti)") {
                        Toggle("", isOn: $tischeVerwenden)
                            .labelsHidden()
                            .tint(DS.C.acc)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Tägliche Schicht-Erinnerung",
                         sub: "Warnung wenn Sitzung länger als 24 Stunden offen (GoBD)") {
                        Toggle("", isOn: $schichtErinnerung)
                            .labelsHidden()
                            .tint(DS.C.acc)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Stornobegründung erzwingen",
                         sub: "Storno ohne Pflichtfeld-Begründung nicht möglich") {
                        Toggle("", isOn: $stornoBegruendung)
                            .labelsHidden()
                            .tint(DS.C.acc)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Mindest-App-Version",
                         sub: "Ältere App-Versionen können sich nicht mehr anmelden") {
                        Text("1.0.0")
                            .dsFont(.mono(14, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                }
            }
            .padding(DS.S.pagePad)
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
                    ERow("TSE-Status", sub: "Fiskaly Cloud-TSE") {
                        DSPill(label: "Aktivierung ausstehend", fg: DS.C.brassText, bg: DS.C.brassBg)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("TSE-Seriennummer", sub: "Wird bei der TSE-Aktivierung vergeben") {
                        Text("—")
                            .dsFont(.sub)
                            .foregroundColor(DS.C.text2)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Offline-Betrieb",
                         sub: "Transaktionen werden lokal gespeichert und bei Reconnect signiert") {
                        DSPill(label: "Bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("ELSTER-Meldung",
                         sub: "Kasse beim Finanzamt melden (einmalig, nach Fiskaly-Aktivierung)") {
                        DSPill(label: "Bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
                    }
                }

                // Info box
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .dsFont(.raw(15))
                        .foregroundColor(DS.C.accT)
                        .padding(.top, 1)
                    Text("Die TSE-Aktivierung erfolgt vor dem Go-live. Der Pilot-Betrieb ohne TSE ist zulässig, muss aber vor dem regulären Betrieb umgestellt werden.")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.accT)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.accBg))
            }
            .padding(DS.S.pagePad)
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
        case .trial:     return DS.C.brassText
        case .pastDue:   return DS.C.dangerText
        case .cancelled: return DS.C.text2
        case nil:        return DS.C.text2
        }
    }

    private var statusBg: Color {
        switch tenant?.subscriptionStatus {
        case .active:    return DS.C.successBg
        case .trial:     return DS.C.brassBg
        case .pastDue:   return DS.C.dangerBg
        case .cancelled: return DS.C.sur2
        case nil:        return DS.C.sur2
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
                    sub:   "Dein aktueller Plan und Abrechnungsdetails."
                )

                if isLoading {
                    ProgressView().progressViewStyle(.circular).frame(maxWidth: .infinity)
                } else {
                    // Plan highlight
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(planLabel)
                                    .dsFont(.heading)
                                    .foregroundColor(DS.C.accT)
                                DSPill(label: statusLabel, fg: statusColor, bg: statusBg)
                            }
                            if tenant?.subscriptionStatus == .trial {
                                Text("14-Tage-Testphase läuft")
                                    .dsFont(.caption)
                                    .foregroundColor(DS.C.accT.opacity(0.75))
                            }
                        }
                        Spacer()
                        if tenant?.plan == .starter || tenant?.subscriptionStatus == .trial {
                            // Stripe-Upgrade kommt in Phase 3 — kein aktiv aussehender Button ohne Funktion
                            DSPill(label: "Plan-Wechsel bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.accBg))

                    // Plan limits
                    ECard {
                        ERow("Geräte", sub: "Starter: max. 1 Gerät") {
                            Text("1 / 1")
                                .dsFont(.mono(14, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                        ERow("Berichts-Zeitraum", sub: "Verfügbare Historien-Tiefe") {
                            Text(reportDays)
                                .dsFont(.raw(14, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                        ERow("Rechnungen & Zahlungsmethoden", sub: "Verwaltung über das Abrechnungs-Portal") {
                            DSPill(label: "Bald verfügbar", fg: DS.C.text2, bg: DS.C.sur2, showDot: false)
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
                        // In-App-Kündigung kommt in Phase 3 — bis dahin der echte Weg:
                        Text("Per E-Mail an support@cashbox.de")
                            .dsFont(.subMed)
                            .foregroundColor(DS.C.text2)
                    }
                }
            }
            .padding(DS.S.pagePad)
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
                    sub:   "Deine Pflichten als Kassenbetreiber und Datenschutzeinstellungen."
                )
                ECard {
                    // AVV/Verfahrensdoku existieren noch nicht — kein „✓ Erstellt" vortäuschen
                    ERow("AVV unterzeichnen",
                         sub: "Auftragsverarbeitungsvertrag (DSGVO-Pflicht) — vor dem Go-live") {
                        DSPill(label: "In Vorbereitung", fg: DS.C.brassText, bg: DS.C.brassBg)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Verfahrensdokumentation",
                         sub: "Pflicht vor produktivem Einsatz (GoBD) — vor dem Go-live") {
                        DSPill(label: "In Vorbereitung", fg: DS.C.brassText, bg: DS.C.brassBg)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Datenspeicherung",
                         sub: "Hetzner Frankfurt · DSGVO-konform") {
                        Text("EU · DE")
                            .dsFont(.sub)
                            .foregroundColor(DS.C.text2)
                    }
                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                    ERow("Daten exportieren",
                         sub: "ZIP-Export aller Betriebsdaten (30 Tage nach Kündigung)") {
                        Text("Per E-Mail an support@cashbox.de")
                            .dsFont(.subMed)
                            .foregroundColor(DS.C.text2)
                    }
                }
            }
            .padding(DS.S.pagePad)
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
                .dsFont(.heading)
                .foregroundColor(DS.C.text)
            Text(sub)
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ECard<C: View>: View {
    @ViewBuilder let content: C

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
                    .dsFont(.bodyMed)
                    .foregroundColor(DS.C.text)
                if let s = sub {
                    Text(s)
                        .dsFont(.caption)
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
    @State private var isFocused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .dsFont(.bodyMed)
                        .foregroundColor(DS.C.text)
                    if let s = sub {
                        Text(s)
                            .dsFont(.caption)
                            .foregroundColor(DS.C.text2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NoAssistantTextField(
                    placeholder: placeholder,
                    text:        $text,
                    uiFont:      UIFont.systemFont(ofSize: 15),
                    uiTextColor: UIColor(DS.C.text),
                    isFocused:   $isFocused
                )
                .frame(height: 44)
                .frame(minWidth: 200, maxWidth: 260)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.bg))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.R.control)
                        .strokeBorder(isFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isFocused ? 1.5 : 1)
                )
                .animation(DS.M.fast, value: isFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showBorder {
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
            }
        }
    }
}

private struct ESmallBtn: View {
    let label:  String
    let danger: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .dsFont(.captionBold)
                .foregroundColor(danger ? DS.C.dangerText : DS.C.text)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    Capsule().fill(danger ? DS.C.dangerBg : DS.C.sur2)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - User Form Sheet

private struct UserFormSheet: View {
    let user:   User?
    let onSave: (String, String, String, UserRole, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var role     = UserRole.staff
    @State private var pin      = ""

    var isEdit:  Bool { user != nil }
    var canSave: Bool { !name.isEmpty && (isEdit || (!email.isEmpty && !password.isEmpty)) }

    private var isDirty: Bool {
        if isEdit { return name != (user?.name ?? "") || role != (user?.role ?? .staff) || !pin.isEmpty }
        return !name.isEmpty || !email.isEmpty || !password.isEmpty || !pin.isEmpty
    }

    var body: some View {
        DSSheetScaffold(
            title: isEdit ? "Mitarbeiter bearbeiten" : "Neuer Mitarbeiter",
            subtitle: isEdit ? user?.name : "Mitarbeiter anlegen",
            icon: isEdit ? "pencil" : "person.badge.plus",
            isDirty: isDirty
        ) {
            VStack(alignment: .leading, spacing: 18) {
                UFormField(label: "Name", placeholder: "Vollständiger Name", text: $name)

                if !isEdit {
                    UFormField(label: "E-Mail", placeholder: "mitarbeiter@example.com", text: $email,
                               keyboardType: .emailAddress, autocapitalizationType: .none)
                    UFormField(label: "Passwort", placeholder: "Mindestens 8 Zeichen", text: $password, isSecure: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Rolle")
                    DSSegmentedControl(selection: $role, options: [
                        (value: UserRole.staff,   label: UserRole.staff.displayName),
                        (value: UserRole.manager, label: UserRole.manager.displayName),
                        (value: UserRole.owner,   label: UserRole.owner.displayName),
                    ])
                }

                UFormField(label: "PIN (4 Stellen, optional)", placeholder: "1234", text: $pin,
                           keyboardType: .numberPad, autocapitalizationType: .none)
            }
        } footer: {
            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(DSSecondaryButton())

                Button {
                    onSave(name, email, password, role, pin.isEmpty ? nil : pin)
                } label: {
                    Text("Speichern")
                }
                .buttonStyle(DSPrimaryButton())
                .disabled(!canSave)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let u = user { name = u.name; role = u.role }
        }
    }
}

// Dünner Alias auf DSTextField (eine Feld-Quelle app-weit)
private struct UFormField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var isSecure:               Bool                          = false
    var keyboardType:           UIKeyboardType                = .default
    var autocapitalizationType: UITextAutocapitalizationType  = .words

    var body: some View {
        DSTextField(label: label, placeholder: placeholder, text: $text,
                    isSecure: isSecure, keyboard: keyboardType,
                    capitalization: autocapitalizationType)
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

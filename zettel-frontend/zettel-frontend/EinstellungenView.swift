// EinstellungenView.swift
// cashbox — Einstellungen: Betriebsdaten, Mitarbeiterverwaltung

import SwiftUI

// MARK: - Root

struct EinstellungenView: View {
    @EnvironmentObject var authStore:     AuthStore
    @EnvironmentObject var usersStore:    UsersStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    enum Tab { case betrieb, mitarbeiter }
    @State private var activeTab = Tab.betrieb

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                EinstellungenTopBar(activeTab: $activeTab)

                if activeTab == .betrieb {
                    BetriebTab()
                } else {
                    MitarbeiterTab()
                        .task {
            await usersStore.loadUsers()
            if !usersStore.users.isEmpty {
                authStore.updatePINUsers(usersStore.users)
            }
        }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }
}

// MARK: - Top Bar

private struct EinstellungenTopBar: View {
    @Binding var activeTab: EinstellungenView.Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Einstellungen")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }
            Spacer()
            HStack(spacing: 0) {
                ETabPill(label: "Betrieb",      isActive: activeTab == .betrieb)      { activeTab = .betrieb }
                ETabPill(label: "Mitarbeiter",  isActive: activeTab == .mitarbeiter)  { activeTab = .mitarbeiter }
            }
            .background(DS.C.sur2)
            .cornerRadius(DS.R.button)
        }
        .padding(.horizontal, 24)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct ETabPill: View {
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                .foregroundColor(isActive ? .white : DS.C.text2)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(isActive ? DS.C.acc : Color.clear)
                .cornerRadius(DS.R.button - 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Betrieb-Tab

private struct BetriebTab: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    private let api = APIClient.shared

    @State private var name       = ""
    @State private var address    = ""
    @State private var vatId      = ""
    @State private var taxNumber  = ""
    @State private var isLoading  = false
    @State private var isSaving   = false
    @State private var error:     AppError?
    @State private var showError  = false
    @State private var showSaved  = false

    @FocusState private var focused: BetriebField?
    enum BetriebField { case name, address, vatId, taxNumber }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ESection("BETRIEBSDATEN (§14 UStG PFLICHTFELDER)") {
                        EInputRow(label: "Betriebsname", placeholder: "Mein Café GmbH", text: $name, focused: $focused, field: .name)
                        EInputRow(label: "Adresse",      placeholder: "Musterstr. 1, 10115 Berlin", text: $address, focused: $focused, field: .address)
                        EInputRow(label: "USt-IdNr.",    placeholder: "DE123456789", text: $vatId, focused: $focused, field: .vatId)
                        EInputRow(label: "Steuernummer", placeholder: "12/345/67890", text: $taxNumber, focused: $focused, field: .taxNumber)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("Betriebsdaten erscheinen auf jedem Kassenbon und sind gesetzlich vorgeschrieben. Änderungen wirken sich auf alle zukünftigen Bons aus.")
                            .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    }
                    .foregroundColor(DS.C.text2)

                    // Speichern-Button
                    Button {
                        Task { await saveTenant() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(showSaved ? "Gespeichert ✓" : "Speichern")
                                    .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.S.buttonHeight)
                    }
                    .background(showSaved ? Color(hex: "27ae60") : DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .disabled(isSaving || name.isEmpty || address.isEmpty)
                    .opacity((isSaving || name.isEmpty || address.isEmpty) ? 0.6 : 1.0)
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: showSaved)
                }
                .padding(20)
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .background(DS.C.bg)
        .task { await loadTenant() }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func loadTenant() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let t: Tenant = try await api.get("/tenants/me")
            name       = t.name
            address    = t.address
            vatId      = t.vatId      ?? ""
            taxNumber  = t.taxNumber  ?? ""
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }

    private func saveTenant() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = UpdateTenantBody(
                name:       name,
                address:    address,
                vatId:      vatId.isEmpty      ? nil : vatId,
                taxNumber:  taxNumber.isEmpty  ? nil : taxNumber
            )
            let _: OkResponse = try await api.patch("/tenants/me", body: body)
            showSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

private struct UpdateTenantBody: Encodable {
    let name:       String
    let address:    String
    let vatId:      String?
    let taxNumber:  String?
}

private struct EInputRow<Field: Hashable>: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var focused:     FocusState<Field?>.Binding
    let field:       Field
    @Environment(\.colorScheme) private var colorScheme

    var isFocused: Bool { focused.wrappedValue == field }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(DS.C.text2)
            TextField(placeholder, text: $text)
                .font(.jakarta(14, weight: .regular))
                .foregroundColor(DS.C.text)
                .focused(focused, equals: field)
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

// MARK: - Mitarbeiter-Tab

private struct MitarbeiterTab: View {
    @EnvironmentObject var usersStore: UsersStore
    @EnvironmentObject var authStore:  AuthStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAddSheet   = false
    @State private var editingUser:   User?
    @State private var error:         AppError?
    @State private var showError      = false
    @State private var showDeleteConfirm = false
    @State private var deletingUser:  User?

    var body: some View {
        HStack(spacing: 0) {
            // Mitarbeiterliste
            VStack(spacing: 0) {
                // Header + Hinzufügen
                HStack {
                    Text("\(usersStore.users.count) Mitarbeiter")
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    if authStore.currentUser?.role == .owner || authStore.currentUser?.role == .manager {
                        Button {
                            showAddSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Hinzufügen")
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

                if usersStore.isLoading {
                    Spacer(); ProgressView().progressViewStyle(.circular); Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(usersStore.users) { user in
                                UserRow(
                                    user:        user,
                                    isSelf:      user.id == authStore.currentUser?.id,
                                    canManage:   authStore.currentUser?.role == .owner || authStore.currentUser?.role == .manager,
                                    onEdit:      { editingUser = user },
                                    onDelete:    {
                                        deletingUser = user
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(DS.C.bg)
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
        .confirmationDialog(
            "Mitarbeiter deaktivieren?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
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

private struct UserRow: View {
    let user:      User
    let isSelf:    Bool
    let canManage: Bool
    let onEdit:    () -> Void
    let onDelete:  () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var roleColor: Color {
        switch user.role {
        case .owner:   return Color(hex: "e67e22")
        case .manager: return DS.C.acc
        case .staff:   return DS.C.text2
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(DS.C.sur2).frame(width: 40, height: 40)
                Text(String(user.name.prefix(1)).uppercased())
                    .font(.jakarta(16, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.name)
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    if isSelf {
                        Text("Ich")
                            .font(.jakarta(8, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.C.accBg)
                            .cornerRadius(4)
                    }
                }
                Text(user.email)
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Text(user.role.displayName)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(roleColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(roleColor.opacity(0.12))
                .cornerRadius(6)

            if canManage {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 30, height: 30)
                        .background(DS.C.sur2)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                if !isSelf {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "e74c3c"))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "e74c3c").opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - User-Formular Sheet

private struct UserFormSheet: View {
    let user: User?
    let onSave: (String, String, String, UserRole, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var role     = UserRole.staff
    @State private var pin      = ""

    @FocusState private var focused: UserField?
    enum UserField { case name, email, password, pin }

    var isEdit: Bool { user != nil }
    var canSave: Bool {
        !name.isEmpty && (isEdit || (!email.isEmpty && !password.isEmpty))
    }

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

                    UFormField(label: "Name", placeholder: "Vollständiger Name", text: $name, focused: $focused, field: .name)

                    if !isEdit {
                        UFormField(label: "E-Mail", placeholder: "mitarbeiter@example.com", text: $email, focused: $focused, field: .email)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                        UFormField(label: "Passwort", placeholder: "Mindestens 8 Zeichen", text: $password, focused: $focused, field: .password, isSecure: true)
                    }

                    // Rolle
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

                    UFormField(label: "PIN (4 Stellen, optional)", placeholder: "1234", text: $pin, focused: $focused, field: .pin)
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
            if let u = user {
                name = u.name
                role = u.role
            }
        }
    }
}

private struct UFormField<Field: Hashable>: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var focused:     FocusState<Field?>.Binding
    let field:       Field
    var isSecure:    Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var isFocused: Bool { focused.wrappedValue == field }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(DS.C.text2)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.jakarta(14, weight: .regular))
            .foregroundColor(DS.C.text)
            .focused(focused, equals: field)
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

private struct ESection<Content: View>: View {
    let title:   String
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
            VStack(spacing: 10) { content }
        }
    }
}

// MARK: - Previews

#Preview("Betrieb") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Mitarbeiter") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    EinstellungenView()
        .environmentObject(AuthStore.previewLoggedIn)
        .environmentObject(UsersStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

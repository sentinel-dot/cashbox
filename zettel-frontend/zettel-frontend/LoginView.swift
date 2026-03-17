// LoginView.swift
// cashbox — Login Screen
// Design: kassensystem-design-system.md §8
// Layout: 2 Spalten — Brand-Fläche (flex) | Formular (400pt fix)

import SwiftUI

// MARK: - LoginView (Root)

struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    /// Nutzerpräferenz für Dark Mode — wird in zettel_frontendApp als preferredColorScheme angewandt
    @AppStorage("usesDarkMode") private var usesDarkMode = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Offline-Banner (immer sichtbar wenn kein Netz)
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 2-Spalten-Layout
                HStack(spacing: 0) {
                    BrandPanel()
                    FormPanel(usesDarkMode: $usesDarkMode)
                        .frame(width: DS.S.formPanelWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(usesDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
    }
}

// MARK: - Brand Panel (Linke Spalte)

private struct BrandPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand-Mark + App-Name
            HStack(spacing: 10) {
                BrandMarkView()
                Text("cashbox")
                    .font(.jakarta(DS.T.topbarAppName, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            // Headline
            Text("Ihr digitales\nKassensystem")
                .font(.jakarta(DS.T.loginHeadline, weight: .semibold))
                .foregroundColor(.white)
                .lineSpacing(2)
                .tracking(-0.5)

            Spacer().frame(height: 12)

            // Subtext
            Text("Einfach, schnell und rechtssicher kassieren — GoBD-konform, TSE-zertifiziert, DSGVO-konform.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 24)

            // Feature-Liste
            VStack(alignment: .leading, spacing: 10) {
                BrandFeatureRow(icon: "checkmark.seal.fill", text: "KassenSichV & GoBD konform")
                BrandFeatureRow(icon: "bolt.shield.fill",    text: "Fiskaly Cloud-TSE integriert")
                BrandFeatureRow(icon: "ipad",                text: "Optimiert für iPad — offline-fähig")
            }

            Spacer()

            // Footer
            Text("© 2026 cashbox · Alle Rechte vorbehalten")
                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.C.brandPanel)
    }
}

// MARK: - Brand Mark (4-Quadrat-Logo)

private struct BrandMarkView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.R.brandMark)
                .fill(Color.white.opacity(0.2))
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

// MARK: - Brand Feature Row

private struct BrandFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: DS.S.featureIconSize, height: DS.S.featureIconSize)
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text(text)
                .font(.jakarta(DS.T.loginFeature, weight: .regular))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

// MARK: - Form Panel (Rechte Spalte)

private struct FormPanel: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @Binding var usesDarkMode: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showError = false
    @State private var showRegister = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Dark-Mode-Toggle (oben rechts)
                HStack {
                    Spacer()
                    DarkModeToggle(isOn: $usesDarkMode)
                }

                Spacer().frame(height: 8)

                // Titel + Untertitel
                Text("Anmelden")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)

                Spacer().frame(height: 4)

                Text("Melden Sie sich mit Ihren Zugangsdaten an")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)

                Spacer().frame(height: 24)

                // E-Mail
                LoginTextField(
                    placeholder: "E-Mail",
                    text: $email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    colorScheme: colorScheme
                )

                Spacer().frame(height: 10)

                // Passwort
                LoginPasswordField(
                    password: $password,
                    showPassword: $showPassword,
                    colorScheme: colorScheme
                )

                Spacer().frame(height: 6)

                // Passwort vergessen
                HStack {
                    Spacer()
                    Button("Passwort vergessen?") {
                        // TODO: POST /auth/forgot-password
                    }
                    .font(.jakarta(DS.T.loginForgot, weight: .regular))
                    .foregroundColor(DS.C.acc)
                }

                Spacer().frame(height: 16)

                // Login-Button
                Button {
                    Task { await performLogin() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Anmelden")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.S.buttonHeight)
                }
                .background(DS.C.acc)
                .cornerRadius(DS.R.button)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity(isLoading || email.isEmpty || password.isEmpty ? 0.6 : 1.0)

                // PIN-Bereich (nur wenn gecachte User vorhanden)
                if !authStore.availableUsers.isEmpty {
                    Spacer().frame(height: 24)
                    PINDivider()
                    Spacer().frame(height: 12)

                    VStack(spacing: 6) {
                        ForEach(authStore.availableUsers) { user in
                            PINUserRow(user: user)
                        }
                    }
                }

                Spacer().frame(height: 20)

                // Registrieren-Link
                HStack(spacing: 4) {
                    Text("Noch kein Konto?")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Button("Jetzt registrieren →") {
                        showRegister = true
                    }
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(DS.C.acc)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 16)

                // Versions-Footer
                Text("v1.0.0 · Keine Schicht offen")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 44)
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
        }
        .background(DS.C.sur)
        .fullScreenCover(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(authStore)
                .environmentObject(networkMonitor)
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func performLogin() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authStore.login(email: email, password: password)
        } catch let appError as AppError {
            error = appError
            showError = true
        } catch {
            self.error = .unknown(error.localizedDescription)
            showError = true
        }
    }
}

// MARK: - Dark Mode Toggle

private struct DarkModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? DS.C.accBg : DS.C.sur2)
                    .frame(width: 38, height: 22)
                    .overlay(
                        Capsule()
                            .strokeBorder(DS.C.brdLight, lineWidth: 1)
                    )
                Circle()
                    .fill(isOn ? DS.C.acc : DS.C.text2)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Dark Mode an" : "Dark Mode aus")
    }
}

// MARK: - Login Text Field

private struct LoginTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    let colorScheme: ColorScheme

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.jakarta(14, weight: .regular))
            .foregroundColor(DS.C.text)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .frame(height: DS.S.inputHeight)
            .background(DS.C.bg)
            .cornerRadius(DS.R.input)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(
                        isFocused ? DS.C.acc : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Login Password Field

private struct LoginPasswordField: View {
    @Binding var password: String
    @Binding var showPassword: Bool
    let colorScheme: ColorScheme

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if showPassword {
                    TextField("Passwort", text: $password)
                } else {
                    SecureField("Passwort", text: $password)
                }
            }
            .font(.jakarta(14, weight: .regular))
            .foregroundColor(DS.C.text)
            .textContentType(.password)
            .focused($isFocused)

            // Auge-Icon (14×14pt laut Spec)
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: DS.S.inputHeight)
        .background(DS.C.bg)
        .cornerRadius(DS.R.input)
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.input)
                .strokeBorder(
                    isFocused ? DS.C.acc : DS.C.brd(colorScheme),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - PIN Divider

private struct PINDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(DS.C.brd(colorScheme))
            Text("oder mit PIN wechseln")
                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                .foregroundColor(DS.C.text2)
                .fixedSize()
            Rectangle()
                .frame(height: 1)
                .foregroundColor(DS.C.brd(colorScheme))
        }
    }
}

// MARK: - PIN User Row

private struct PINUserRow: View {
    let user: AuthUser

    @EnvironmentObject var authStore: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showPINEntry = false
    @State private var pin = ""
    @State private var isLoadingPIN = false
    @State private var pinError: AppError?
    @State private var showPINError = false
    @State private var isHovered = false

    var body: some View {
        Button {
            pin = ""
            showPINEntry = true
        } label: {
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(user.role == .owner ? DS.C.accBg : DS.C.sur2)
                        .frame(width: DS.S.avatarSize, height: DS.S.avatarSize)
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(user.role == .owner ? DS.C.accT : DS.C.text2)
                }

                // Name + Rolle
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text(user.role.displayName)
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                // Pfeil (13×13pt laut Spec)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isHovered ? DS.C.accBg : DS.C.bg)
            .cornerRadius(DS.R.pinRow)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.pinRow)
                    .strokeBorder(
                        isHovered ? DS.C.acc : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sheet(isPresented: $showPINEntry) {
            PINEntrySheet(
                user: user,
                pin: $pin,
                isLoading: $isLoadingPIN
            ) {
                Task { await loginWithPIN() }
            }
        }
        .alert("Fehler", isPresented: $showPINError) {
            Button("OK") { pinError = nil }
        } message: {
            Text(pinError?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func loginWithPIN() async {
        isLoadingPIN = true
        defer { isLoadingPIN = false }
        do {
            try await authStore.loginWithPin(pin: pin)
        } catch let appError as AppError {
            pinError = appError
            showPINError = true
            pin = ""
        } catch {
            pinError = .unknown(error.localizedDescription)
            showPINError = true
            pin = ""
        }
    }
}

// MARK: - PIN Entry Sheet

private struct PINEntrySheet: View {
    let user: AuthUser
    @Binding var pin: String
    @Binding var isLoading: Bool
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let keys = ["1","2","3","4","5","6","7","8","9","","0","⌫"]

    var body: some View {
        VStack(spacing: 24) {
            // Titel
            Text("PIN für \(user.name)")
                .font(.jakarta(17, weight: .semibold))
                .foregroundColor(DS.C.text)

            // PIN-Punkte (4 Stellen)
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? DS.C.acc : DS.C.sur2)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().strokeBorder(DS.C.acc.opacity(0.3), lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.1), value: pin.count)
                }
            }

            // Numpad
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(height: DS.S.touchTarget)
                    } else {
                        Button {
                            handleKey(key)
                        } label: {
                            Text(key)
                                .font(.jakarta(20, weight: .medium))
                                .foregroundColor(DS.C.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: DS.S.touchTarget)
                                .background(DS.C.sur2)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(key != "⌫" && pin.count >= 4)
                    }
                }
            }
            .padding(.horizontal)

            // Buttons
            HStack(spacing: 10) {
                Button("Abbrechen") {
                    pin = ""
                    dismiss()
                }
                .font(.jakarta(14, weight: .medium))
                .foregroundColor(DS.C.text2)
                .frame(maxWidth: .infinity, minHeight: DS.S.touchTarget)
                .background(DS.C.sur2)
                .cornerRadius(DS.R.button)
                .buttonStyle(.plain)

                Button {
                    onSubmit()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Bestätigen")
                                .font(.jakarta(14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.S.touchTarget)
                }
                .background(pin.count == 4 && !isLoading ? DS.C.acc : DS.C.acc.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(pin.count < 4 || isLoading)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: pin.count == 4)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
        } else if pin.count < 4 {
            pin += key
            if pin.count == 4 {
                // Auto-Submit nach letzter Ziffer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onSubmit()
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Light Mode — mit PIN-Usern") {
    LoginView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    LoginView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

#Preview("Offline-Banner") {
    LoginView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Kein PIN-Cache") {
    LoginView()
        .environmentObject(AuthStore())
        .environmentObject(NetworkMonitor.preview)
}

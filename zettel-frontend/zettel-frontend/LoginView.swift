// LoginView.swift
// cashbox — Login Screen
// Layout: 2 Spalten — Brand-Fläche (flex) | PIN-Panel (420pt fix)

import SwiftUI

// MARK: - LoginView (Root)

struct LoginView: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @AppStorage("usesDarkMode") private var usesDarkMode = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let reason = authStore.sessionExpiredReason {
                    SessionExpiredBanner(message: reason) {
                        authStore.sessionExpiredReason = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    BrandPanel(usesDarkMode: $usesDarkMode)
                    LoginPanel()
                        .frame(width: DS.S.formPanelWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(usesDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .animation(.easeInOut(duration: 0.3), value: authStore.sessionExpiredReason != nil)
    }
}

// MARK: - Brand Panel (Linke Spalte)

private struct BrandPanel: View {
    @Binding var usesDarkMode: Bool

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Guten Morgen," }
        if h < 17 { return "Guten Tag," }
        return "Guten Abend,"
    }

    private var dateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "d. MMMM yyyy"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "de_DE")
        tf.timeStyle = .short
        return "\(df.string(from: Date())) · \(tf.string(from: Date())) Uhr"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand mark + Name
            HStack(spacing: 11) {
                GridBrandMark()
                Text("Kassensystem")
                    .font(.jakarta(16, weight: .semibold))
                    .foregroundColor(.white)
                    .tracking(-0.3)
            }

            Spacer()

            // Tagline
            (Text(greeting + "\n").foregroundColor(.white)
             + Text("bereit für die\nneue Schicht.").foregroundColor(.white.opacity(0.6)))
                .font(.jakarta(26, weight: .semibold))
                .lineSpacing(2)
                .tracking(-0.5)

            Spacer()

            // Meta + Dark-Mode-Toggle
            VStack(alignment: .leading, spacing: 14) {
                Text(dateTimeString)
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .lineSpacing(4)

                HStack(spacing: 8) {
                    Text("Dark Mode")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                    DarkModeToggle(isOn: $usesDarkMode)
                }
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.C.brandPanel)
    }
}

// MARK: - 4-Dot Grid Brand Mark

private struct GridBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.R.brandMark)
                .fill(Color.white.opacity(0.2))
                .frame(width: DS.S.brandMarkSize, height: DS.S.brandMarkSize)
            HStack(spacing: 3) {
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 6)
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 6)
                }
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 6)
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 6)
                }
            }
        }
    }
}

// MARK: - Session-Abgelaufen-Banner

private struct SessionExpiredBanner: View {
    let message:   String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "c0392b"))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Login Panel (Rechte Spalte, Root)

private struct LoginPanel: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var showPasswordForm = false
    @State private var showRegister     = false

    var body: some View {
        Group {
            if showPasswordForm || authStore.availableUsers.isEmpty {
                EmailPasswordPanel(
                    showRegister:     $showRegister,
                    onSwitchToPIN:    authStore.availableUsers.isEmpty ? nil : { showPasswordForm = false }
                )
            } else {
                PINPanel(onSwitchToPassword: { showPasswordForm = true })
            }
        }
        .background(DS.C.sur)
        .fullScreenCover(isPresented: $showRegister) {
            OnboardingView()
                .environmentObject(authStore)
                .environmentObject(networkMonitor)
        }
    }
}

// MARK: - PIN Panel

private struct PINPanel: View {
    let onSwitchToPassword: () -> Void

    @EnvironmentObject var authStore: AuthStore
    @Environment(\.colorScheme) private var cs

    @State private var selectedUser:  AuthUser?
    @State private var pin            = ""
    @State private var pinErrorMsg:   String?
    @State private var pinState:      PINState = .idle
    @State private var isLoading      = false

    private enum PINState { case idle, error }

    private let digits: [(String, String?)] = [
        ("1", nil), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("", nil), ("0", nil), ("⌫", nil),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Wer bist du? ──────────────────────────────
                Text("Wer bist du?")
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .padding(.bottom, 12)

                VStack(spacing: 6) {
                    ForEach(authStore.availableUsers) { user in
                        UserCard(
                            user:     user,
                            selected: selectedUser?.id == user.id,
                            cs:       cs
                        ) {
                            selectedUser = user
                            pin          = ""
                            pinErrorMsg  = nil
                            pinState     = .idle
                        }
                    }
                }
                .padding(.bottom, 20)

                // ── Divider ───────────────────────────────────
                Rectangle()
                    .fill(DS.C.brd(cs))
                    .frame(height: 1)
                    .padding(.bottom, 20)

                // ── PIN eingeben ──────────────────────────────
                Text("PIN eingeben")
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .padding(.bottom, 12)

                let greeting = "Hallo, \(selectedUser.map { $0.name } ?? "Gast") 👋"
                Text(greeting)
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .padding(.bottom, 16)

                // PIN-Dots
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(dotFill(i))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(dotBorder(i), lineWidth: 2)
                            )
                            .animation(.easeInOut(duration: 0.1), value: pin.count)
                            .animation(.easeInOut(duration: 0.1), value: pinState)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

                // Fehlertext
                Text(pinErrorMsg ?? " ")
                    .font(.jakarta(11, weight: .medium))
                    .foregroundColor(DS.C.danger)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                // Numpad
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(digits.indices, id: \.self) { i in
                        let (d, sub) = digits[i]
                        NumpadButton(digit: d, sub: sub, isLoading: isLoading && d != "⌫") {
                            handleKey(d)
                        }
                    }
                }
                .padding(.bottom, 14)

                // Fallback-Link
                Button {
                    onSwitchToPassword()
                } label: {
                    Text("PIN vergessen? Mit Passwort anmelden →")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onAppear {
            if selectedUser == nil {
                selectedUser = authStore.availableUsers.first
            }
        }
    }

    private func dotFill(_ i: Int) -> Color {
        if pinState == .error && i < 4   { return DS.C.danger }
        if i < pin.count                  { return DS.C.acc }
        return .clear
    }

    private func dotBorder(_ i: Int) -> Color {
        if pinState == .error && i < 4   { return DS.C.danger }
        if i < pin.count                  { return DS.C.acc }
        return DS.C.brdLight
    }

    private func handleKey(_ key: String) {
        guard !isLoading else { return }
        pinErrorMsg = nil
        pinState    = .idle
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
        } else if key.isEmpty {
            // leere Taste — nichts tun
        } else if pin.count < 4 {
            pin += key
            if pin.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Task { await submitPIN() }
                }
            }
        }
    }

    private func submitPIN() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authStore.loginWithPin(pin: pin)
        } catch {
            pinState   = .error
            pinErrorMsg = "Falscher PIN. Bitte erneut versuchen."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                pin        = ""
                pinState   = .idle
                pinErrorMsg = nil
            }
        }
    }
}

// MARK: - User Card

private struct UserCard: View {
    let user:     AuthUser
    let selected: Bool
    let cs:       ColorScheme
    let onTap:    () -> Void

    private var avatarBg: Color {
        switch user.role {
        case .owner:   return DS.C.accBg
        case .manager: return Color.adaptive(light: "fff3e0", dark: "2e1f0a")
        case .staff:   return DS.C.sur2
        }
    }

    private var avatarFg: Color {
        switch user.role {
        case .owner:   return DS.C.accT
        case .manager: return Color.adaptive(light: "8a5010", dark: "f0a840")
        case .staff:   return DS.C.text2
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(selected ? DS.C.acc : avatarBg)
                        .frame(width: DS.S.avatarSize, height: DS.S.avatarSize)
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(selected ? .white : avatarFg)
                }

                // Name + Rolle
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(selected ? DS.C.accT : DS.C.text)
                    Text(user.role.displayName)
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                // Checkmark-Kreis
                ZStack {
                    Circle()
                        .fill(selected ? DS.C.acc : .clear)
                        .frame(width: 18, height: 18)
                    Circle()
                        .strokeBorder(selected ? DS.C.acc : DS.C.brd(cs), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? DS.C.accBg : .clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? DS.C.acc : DS.C.brd(cs), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Numpad Button

private struct NumpadButton: View {
    let digit:     String
    let sub:       String?
    let isLoading: Bool
    let onTap:     () -> Void

    @Environment(\.colorScheme) private var cs

    var body: some View {
        if digit.isEmpty {
            Color.clear.frame(height: 52)
        } else {
            Button(action: onTap) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(DS.C.acc)
                    } else if digit == "⌫" {
                        Image(systemName: "delete.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    } else {
                        VStack(spacing: 1) {
                            Text(digit)
                                .font(.jakarta(18, weight: .semibold))
                                .foregroundColor(DS.C.text)
                            if let sub {
                                Text(sub)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(DS.C.text2)
                                    .tracking(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(digit == "⌫" ? DS.C.sur2 : DS.C.bg)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(DS.C.brd(cs), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }
}

// MARK: - Email/Password Panel

private struct EmailPasswordPanel: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var cs

    @Binding var showRegister: Bool
    let onSwitchToPIN: (() -> Void)?

    @State private var email       = ""
    @State private var password    = ""
    @State private var showPW      = false
    @State private var isLoading   = false
    @State private var error:        AppError?
    @State private var showError   = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // Zurück zu PIN (wenn vorhanden)
                if let switchBack = onSwitchToPIN {
                    Button {
                        switchBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Zur PIN-Anmeldung")
                                .font(.jakarta(12, weight: .medium))
                        }
                        .foregroundColor(DS.C.acc)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }

                Text("Mit Passwort anmelden")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .padding(.bottom, 4)

                Text("Melden Sie sich mit Ihren Zugangsdaten an")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .padding(.bottom, 24)

                LoginTextField(
                    placeholder:     "E-Mail",
                    text:            $email,
                    keyboardType:    .emailAddress,
                    textContentType: .emailAddress,
                    colorScheme:     cs
                )
                .padding(.bottom, 10)

                LoginPasswordField(
                    password:    $password,
                    showPassword: $showPW,
                    colorScheme: cs
                )
                .padding(.bottom, 6)

                HStack {
                    Spacer()
                    Button("Passwort vergessen?") {}
                        .font(.jakarta(DS.T.loginForgot, weight: .regular))
                        .foregroundColor(DS.C.acc)
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 16)

                Button {
                    Task { await doLogin() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
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
                .buttonStyle(.plain)
                .padding(.bottom, 20)

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
            }
            .padding(.top, 44)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func doLogin() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await authStore.login(email: email, password: password)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
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
                    .fill(isOn ? Color.white.opacity(0.3) : Color.white.opacity(0.2))
                    .frame(width: 38, height: 22)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                Circle()
                    .fill(isOn ? DS.C.acc : Color.white.opacity(0.5))
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
    let placeholder:     String
    @Binding var text:   String
    var keyboardType:    UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    let colorScheme:     ColorScheme

    @State private var isFocused = false

    var body: some View {
        NoAssistantTextField(
            placeholder:            placeholder,
            text:                   $text,
            keyboardType:           keyboardType,
            uiFont:                 UIFont.systemFont(ofSize: 14),
            uiTextColor:            UIColor(DS.C.text),
            textContentType:        textContentType,
            autocapitalizationType: .none,
            autocorrectionType:     .no,
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

// MARK: - Login Password Field

private struct LoginPasswordField: View {
    @Binding var password:     String
    @Binding var showPassword: Bool
    let colorScheme:           ColorScheme

    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            NoAssistantTextField(
                placeholder:     "Passwort",
                text:            $password,
                uiFont:          UIFont.systemFont(ofSize: 14),
                uiTextColor:     UIColor(DS.C.text),
                isSecure:        !showPassword,
                textContentType: .password,
                isFocused:       $isFocused
            )
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 14))
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
                .strokeBorder(isFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Previews

#Preview("PIN-Login (mit Usern)") {
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

#Preview("Kein PIN-Cache → E-Mail-Form") {
    LoginView()
        .environmentObject(AuthStore())
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline-Banner") {
    LoginView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

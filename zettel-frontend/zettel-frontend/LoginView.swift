// LoginView.swift
// cashbox — Login Screen
// Layout: 2 Spalten — Brand-Fläche (flex, Nacht-Olive) | PIN-Panel (420pt fix)
// Design v3: Committed-Farbfläche links, Touch-Numpad 56pt, SF Pro.

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
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .animation(DS.M.slow, value: authStore.sessionExpiredReason != nil)
    }
}

// MARK: - Brand Panel (Linke Spalte — Nacht-Olive, committed)

private struct BrandPanel: View {
    @Binding var usesDarkMode: Bool

    // Helle Akzentfarbe auf dunklem Panel (Ledger Green, Dark-Variante)
    private let leaf = Color(hex: "AECB6E")

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Guten Morgen," }
        if h < 17 { return "Guten Tag," }
        return "Guten Abend,"
    }

    private var dateTimeString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEEE, d. MMMM yyyy"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "de_DE")
        tf.timeStyle = .short
        return "\(df.string(from: Date())) · \(tf.string(from: Date())) Uhr"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand mark + Name
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.R.brandMark)
                        .fill(leaf)
                        .frame(width: 34, height: 34)
                    Image(systemName: "eurosign")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "1C2413"))
                }
                Text("cashbox")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            // Tagline
            (Text(greeting + "\n").foregroundColor(.white)
             + Text("bereit für die\nneue Schicht.").foregroundColor(leaf))
                .font(.system(size: 34, weight: .bold))
                .lineSpacing(3)

            Spacer()

            // Meta + Dark-Mode-Toggle
            VStack(alignment: .leading, spacing: 16) {
                Text(dateTimeString)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.55))

                HStack(spacing: 10) {
                    Text("Dark Mode")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                    Toggle("", isOn: $usesDarkMode)
                        .labelsHidden()
                        .tint(leaf.opacity(0.6))
                }
            }
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.C.brandPanel)
    }
}

// MARK: - Session-Abgelaufen-Banner

private struct SessionExpiredBanner: View {
    let message:   String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(Color(hex: "9E2F22"))
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

                // Wer bist du?
                DSSectionLabel(text: "Wer bist du?")
                    .padding(.bottom, 12)

                VStack(spacing: 8) {
                    ForEach(authStore.availableUsers) { user in
                        UserCard(
                            user:     user,
                            selected: selectedUser?.id == user.id
                        ) {
                            selectedUser = user
                            pin          = ""
                            pinErrorMsg  = nil
                            pinState     = .idle
                        }
                    }
                }
                .padding(.bottom, 22)

                Rectangle()
                    .fill(DS.C.brdAdaptive)
                    .frame(height: 1)
                    .padding(.bottom, 22)

                // PIN eingeben
                Text("Hallo, \(selectedUser.map { $0.name } ?? "Gast") 👋")
                    .font(DS.F.heading)
                    .foregroundColor(DS.C.text)
                    .padding(.bottom, 4)
                Text("Gib deinen 4-stelligen PIN ein.")
                    .font(DS.F.sub)
                    .foregroundColor(DS.C.text2)
                    .padding(.bottom, 18)

                // PIN-Dots
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(dotFill(i))
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().strokeBorder(dotBorder(i), lineWidth: 2)
                            )
                            .animation(DS.M.fast, value: pin.count)
                            .animation(DS.M.fast, value: pinState)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

                // Fehlertext
                Text(pinErrorMsg ?? " ")
                    .font(DS.F.caption)
                    .foregroundColor(DS.C.dangerText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 10)

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
                .padding(.bottom, 16)

                // Fallback-Link
                Button {
                    onSwitchToPassword()
                } label: {
                    Text("PIN vergessen? Mit Passwort anmelden →")
                        .font(DS.F.caption)
                        .foregroundColor(DS.C.text2)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
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
        return DS.C.brdAdaptive
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
    let onTap:    () -> Void

    private var avatarBg: Color {
        switch user.role {
        case .owner:   return DS.C.accBg
        case .manager: return DS.C.brassBg
        case .staff:   return DS.C.sur2
        }
    }

    private var avatarFg: Color {
        switch user.role {
        case .owner:   return DS.C.accT
        case .manager: return DS.C.brassText
        case .staff:   return DS.C.text2
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(selected ? DS.C.acc : avatarBg)
                        .frame(width: DS.S.avatarSize, height: DS.S.avatarSize)
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selected ? .white : avatarFg)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selected ? DS.C.accT : DS.C.text)
                    Text(user.role.displayName)
                        .font(DS.F.caption)
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(selected ? DS.C.acc : .clear)
                        .frame(width: 20, height: 20)
                    Circle()
                        .strokeBorder(selected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .fill(selected ? DS.C.accBg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(selected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.input))
            .animation(DS.M.fast, value: selected)
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

    var body: some View {
        if digit.isEmpty {
            Color.clear.frame(height: 56)
        } else {
            Button(action: onTap) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(DS.C.accT)
                    } else if digit == "⌫" {
                        Image(systemName: "delete.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(DS.C.text2)
                    } else {
                        VStack(spacing: 1) {
                            Text(digit)
                                .font(.system(size: 22, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(DS.C.text)
                            if let sub {
                                Text(sub)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(DS.C.text2)
                                    .tracking(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(NumpadPressStyle(isDelete: digit == "⌫"))
            .disabled(isLoading)
        }
    }
}

private struct NumpadPressStyle: ButtonStyle {
    let isDelete: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.R.pinRow)
                    .fill(configuration.isPressed ? DS.C.sur2 : (isDelete ? DS.C.sur2.opacity(0.6) : DS.C.bg))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

// MARK: - Email/Password Panel

private struct EmailPasswordPanel: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

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
                                .font(.system(size: 13, weight: .semibold))
                            Text("Zur PIN-Anmeldung")
                                .font(DS.F.subMed)
                        }
                        .foregroundColor(DS.C.accT)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                }

                Text("Mit Passwort anmelden")
                    .font(DS.F.title)
                    .foregroundColor(DS.C.text)
                    .padding(.bottom, 6)

                Text("Melde dich mit deinen Zugangsdaten an.")
                    .font(DS.F.sub)
                    .foregroundColor(DS.C.text2)
                    .padding(.bottom, 26)

                LoginTextField(
                    placeholder:     "E-Mail",
                    text:            $email,
                    keyboardType:    .emailAddress,
                    textContentType: .emailAddress
                )
                .padding(.bottom, 10)

                LoginPasswordField(
                    password:    $password,
                    showPassword: $showPW
                )
                .padding(.bottom, 8)

                HStack {
                    Spacer()
                    Button("Passwort vergessen?") {}
                        .font(DS.F.sub)
                        .foregroundColor(DS.C.accT)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                }
                .padding(.bottom, 10)

                Button {
                    Task { await doLogin() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("Anmelden")
                        }
                    }
                }
                .buttonStyle(DSPrimaryButton())
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .padding(.bottom, 22)

                HStack(spacing: 4) {
                    Text("Noch kein Konto?")
                        .font(DS.F.sub)
                        .foregroundColor(DS.C.text2)
                    Button("Jetzt registrieren →") {
                        showRegister = true
                    }
                    .font(DS.F.subBold)
                    .foregroundColor(DS.C.accT)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
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

// MARK: - Login Text Field

private struct LoginTextField: View {
    let placeholder:     String
    @Binding var text:   String
    var keyboardType:    UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    @State private var isFocused = false

    var body: some View {
        NoAssistantTextField(
            placeholder:            placeholder,
            text:                   $text,
            keyboardType:           keyboardType,
            uiFont:                 UIFont.systemFont(ofSize: 16),
            uiTextColor:            UIColor(DS.C.text),
            textContentType:        textContentType,
            autocapitalizationType: .none,
            autocorrectionType:     .no,
            isFocused:              $isFocused
        )
        .padding(.horizontal, 14)
        .frame(height: DS.S.inputHeight)
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.input)
                .strokeBorder(isFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(DS.M.fast, value: isFocused)
    }
}

// MARK: - Login Password Field

private struct LoginPasswordField: View {
    @Binding var password:     String
    @Binding var showPassword: Bool

    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            NoAssistantTextField(
                placeholder:     "Passwort",
                text:            $password,
                uiFont:          UIFont.systemFont(ofSize: 16),
                uiTextColor:     UIColor(DS.C.text),
                isSecure:        !showPassword,
                textContentType: .password,
                isFocused:       $isFocused
            )
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: DS.S.inputHeight)
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.input)
                .strokeBorder(isFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(DS.M.fast, value: isFocused)
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

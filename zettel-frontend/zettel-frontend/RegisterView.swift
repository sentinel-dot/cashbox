// RegisterView.swift
// cashbox — Registrierungsformular → POST /onboarding/register
// Entspricht Design System Tokens. 2-Spalten: Brand-Panel links, Formular rechts.

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            RegisterBrandPanel()
            RegisterFormPanel(onSuccess: { dismiss() }, onBack: { dismiss() })
                .frame(width: DS.S.formPanelWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.bg)
        .ignoresSafeArea()
    }
}

// MARK: - Brand Panel

private struct RegisterBrandPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RegisterBrandMark()
                Text("cashbox")
                    .font(.jakarta(DS.T.topbarAppName, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            Text("In 2 Minuten\nstartbereit")
                .font(.jakarta(DS.T.loginHeadline, weight: .semibold))
                .foregroundColor(.white)
                .tracking(-0.5)
                .lineSpacing(2)

            Spacer().frame(height: 12)

            Text("Konto anlegen, Kassensitzung öffnen, loslegen — GoBD-konform ab Tag 1.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 28)

            VStack(alignment: .leading, spacing: 14) {
                RegisterStep(number: "1", text: "Betriebsdaten eingeben")
                RegisterStep(number: "2", text: "14 Tage kostenlos testen")
                RegisterStep(number: "3", text: "Abo wählen — jederzeit kündbar")
            }

            Spacer()

            Text("© 2026 cashbox · Alle Rechte vorbehalten")
                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.C.brandPanel)
    }
}

private struct RegisterBrandMark: View {
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

private struct RegisterStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 22, height: 22)
                Text(number)
                    .font(.jakarta(11, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(text)
                .font(.jakarta(DS.T.loginFeature, weight: .regular))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

// MARK: - Form Panel

private struct RegisterFormPanel: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    let onSuccess: () -> Void
    let onBack: () -> Void

    @State private var businessName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var address = ""
    @State private var taxNumber = ""
    @State private var deviceName = "iPad Theke"

    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showError = false

    private var canSubmit: Bool {
        Validators.notEmpty(businessName).isValid &&
        Validators.email(email).isValid &&
        Validators.password(password).isValid &&
        Validators.notEmpty(address).isValid &&
        Validators.taxNumber(taxNumber).isValid &&
        Validators.notEmpty(deviceName).isValid &&
        !isLoading
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Zurück-Link
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Zurück zum Login")
                            .font(.jakarta(12, weight: .medium))
                    }
                    .foregroundColor(DS.C.acc)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 16)

                Text("Konto erstellen")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)

                Spacer().frame(height: 4)

                Text("14 Tage kostenlos — kein Kreditkarte nötig")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)

                Spacer().frame(height: 24)

                // ── Betrieb ──────────────────────────────────────
                FormSectionHeader("Betriebsdaten")

                Spacer().frame(height: 10)

                RegisterField(
                    label: "Unternehmensname",
                    placeholder: "z.B. Shisha Lounge Berlin",
                    text: $businessName,
                    colorScheme: colorScheme,
                    validator: Validators.notEmpty
                )

                Spacer().frame(height: 10)

                RegisterField(
                    label: "Vollständige Adresse",
                    placeholder: "Musterstraße 1, 10115 Berlin",
                    text: $address,
                    colorScheme: colorScheme,
                    validator: Validators.notEmpty
                )

                Spacer().frame(height: 10)

                RegisterField(
                    label: "Steuernummer",
                    placeholder: "12/345/67890",
                    text: $taxNumber,
                    keyboardType: .default,
                    colorScheme: colorScheme,
                    validator: Validators.taxNumber
                )

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Findet sich im letzten Steuerbescheid oder beim Finanzamt")
                        .font(.jakarta(10, weight: .regular))
                }
                .foregroundColor(DS.C.text2)
                .padding(.top, 5)

                Spacer().frame(height: 20)

                // ── Account ──────────────────────────────────────
                FormSectionHeader("Zugangsdaten")

                Spacer().frame(height: 10)

                RegisterField(
                    label: "E-Mail",
                    placeholder: "ihr@email.de",
                    text: $email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    colorScheme: colorScheme,
                    validator: Validators.email
                )

                Spacer().frame(height: 10)

                RegisterField(
                    label: "Passwort",
                    placeholder: "Mindestens 8 Zeichen",
                    text: $password,
                    textContentType: .newPassword,
                    isSecure: true,
                    colorScheme: colorScheme,
                    validator: Validators.password
                )

                Spacer().frame(height: 20)

                // ── Gerät ────────────────────────────────────────
                FormSectionHeader("Gerät")

                Spacer().frame(height: 10)

                RegisterField(
                    label: "Gerätename",
                    placeholder: "z.B. iPad Theke",
                    text: $deviceName,
                    colorScheme: colorScheme,
                    validator: Validators.notEmpty
                )

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Erscheint auf jedem Bon (§ 6 KassenSichV)")
                        .font(.jakarta(10, weight: .regular))
                }
                .foregroundColor(DS.C.text2)
                .padding(.top, 5)

                Spacer().frame(height: 24)

                // ── Submit ───────────────────────────────────────
                Button {
                    Task { await performRegister() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("Konto erstellen & loslegen")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.S.buttonHeight)
                }
                .background(canSubmit ? DS.C.acc : DS.C.acc.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(!canSubmit)
                .animation(.easeInOut(duration: 0.15), value: canSubmit)
                .buttonStyle(.plain)

                Spacer().frame(height: 12)

                // Hinweis
                Text("Mit der Registrierung akzeptieren Sie unsere AGB und Datenschutzbestimmungen. TSE-Meldepflicht beim Finanzamt (ELSTER) liegt beim Betreiber.")
                    .font(.jakarta(9, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 44)
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
        }
        .background(DS.C.sur)
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func performRegister() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authStore.register(
                businessName: businessName.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                address: address.trimmingCharacters(in: .whitespaces),
                taxNumber: taxNumber.trimmingCharacters(in: .whitespaces),
                deviceName: deviceName.trimmingCharacters(in: .whitespaces)
            )
            onSuccess()
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

// MARK: - Validation

enum ValidationState: Equatable {
    case idle
    case valid
    case invalid(String)

    var isValid: Bool { if case .valid = self { return true }; return false }
    var isInvalid: Bool { if case .invalid = self { return true }; return false }

    var message: String? {
        if case .invalid(let msg) = self { return msg }
        return nil
    }
}

enum Validators {
    static func notEmpty(_ value: String) -> ValidationState {
        value.trimmingCharacters(in: .whitespaces).isEmpty
            ? .invalid("Pflichtfeld")
            : .valid
    }

    static func email(_ value: String) -> ValidationState {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .invalid("Pflichtfeld") }
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
            ? .valid
            : .invalid("Bitte gültige E-Mail eingeben")
    }

    static func password(_ value: String) -> ValidationState {
        if value.isEmpty { return .invalid("Pflichtfeld") }
        if value.count < 8 { return .invalid("Mindestens 8 Zeichen") }
        return .valid
    }

    static func taxNumber(_ value: String) -> ValidationState {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .invalid("Pflichtfeld") }
        // Akzeptiert gängige DE-Formate: 12/345/67890, 1234567890, 12 345 67890
        let digits = trimmed.filter(\.isNumber)
        return digits.count >= 10
            ? .valid
            : .invalid("Zu kurz — prüfe die Steuernummer auf deinem Steuerbescheid")
    }
}

// MARK: - Password Strength

enum PasswordStrength: Int {
    case empty = 0, weak = 1, fair = 2, strong = 3, veryStrong = 4

    static func evaluate(_ password: String) -> PasswordStrength {
        if password.isEmpty { return .empty }
        var score = 0
        if password.count >= 8  { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase) { score += 1 }
        if password.contains(where: { "!@#$%^&*()_+-=[]{}|;':\",./<>?".contains($0) }) { score += 1 }
        return PasswordStrength(rawValue: min(score, 4)) ?? .weak
    }

    var label: String {
        switch self {
        case .empty:      return ""
        case .weak:       return "Schwach"
        case .fair:       return "Ausreichend"
        case .strong:     return "Stark"
        case .veryStrong: return "Sehr stark"
        }
    }

    var color: Color {
        switch self {
        case .empty:      return Color.clear
        case .weak:       return Color(hex: "ef4444")
        case .fair:       return Color(hex: "f97316")
        case .strong:     return Color(hex: "eab308")
        case .veryStrong: return Color(hex: "22c55e")
        }
    }
}

private struct PasswordStrengthBar: View {
    let password: String

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }

    var body: some View {
        if !password.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { segment in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment <= strength.rawValue ? strength.color : Color.gray.opacity(0.2))
                            .frame(maxWidth: .infinity)
                            .frame(height: 3)
                            .animation(.easeInOut(duration: 0.25), value: strength.rawValue)
                    }
                }
                if !strength.label.isEmpty {
                    Text(strength.label)
                        .font(.jakarta(10, weight: .medium))
                        .foregroundColor(strength.color)
                        .animation(.easeInOut(duration: 0.2), value: strength.label)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Wiederverwendbare Komponenten

private struct FormSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.jakarta(DS.T.sectionHeader, weight: .regular))
            .foregroundColor(DS.C.text2)
            .tracking(0.8)
    }
}

private struct RegisterField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var isSecure = false
    let colorScheme: ColorScheme
    var validator: ((String) -> ValidationState)? = nil

    @State private var focused      = false
    @State private var showPassword = false
    @State private var touched      = false  // erst nach erstem Verlassen des Felds validieren

    private var validation: ValidationState {
        guard touched, let validate = validator else { return .idle }
        return validate(text)
    }

    private var borderColor: Color {
        if focused { return DS.C.acc }
        switch validation {
        case .idle:    return DS.C.brd(colorScheme)
        case .valid:   return Color(hex: "22c55e")
        case .invalid: return Color(hex: "ef4444")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Label-Zeile
            HStack(spacing: 5) {
                Text(label)
                    .font(.jakarta(11, weight: .medium))
                    .foregroundColor(DS.C.text2)
                Spacer()
                // Validierungs-Icon (erscheint nach erstem Verlassen)
                if touched {
                    switch validation {
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "22c55e"))
                            .transition(.scale.combined(with: .opacity))
                    case .invalid:
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "ef4444"))
                            .transition(.scale.combined(with: .opacity))
                    case .idle:
                        EmptyView()
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: validation)

            // Input-Feld
            HStack {
                NoAssistantTextField(
                    placeholder:            placeholder,
                    text:                   $text,
                    keyboardType:           keyboardType,
                    uiFont:                 UIFont.systemFont(ofSize: 14),
                    uiTextColor:            UIColor(DS.C.text),
                    isSecure:               isSecure && !showPassword,
                    textContentType:        textContentType,
                    autocapitalizationType: keyboardType == .emailAddress ? .none : .words,
                    autocorrectionType:     .no,
                    isFocused:              $focused
                )

                // Auge (Passwort) oder Validierungs-Icon rechts im Feld
                if isSecure {
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundColor(DS.C.text2)
                            .frame(width: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: DS.S.inputHeight)
            .background(DS.C.bg)
            .cornerRadius(DS.R.input)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(borderColor, lineWidth: validation == .idle ? 1 : 1.5)
            )
            .animation(.easeInOut(duration: 0.2), value: borderColor.description)
            .onChange(of: focused) { _, isFocused in
                // touched = true sobald Feld erstmals verlassen
                if !isFocused && !text.isEmpty { touched = true }
            }

            // Fehlermeldung (animiert einblenden)
            if let message = validation.message {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(message)
                        .font(.jakarta(10, weight: .regular))
                }
                .foregroundColor(Color(hex: "ef4444"))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Passwort-Stärke (nur bei isSecure)
            if isSecure {
                PasswordStrengthBar(password: text)
                    .animation(.easeInOut(duration: 0.2), value: text)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: validation)
    }
}

// MARK: - Preview

#Preview("RegisterView") {
    RegisterView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("RegisterView — Dark") {
    RegisterView()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

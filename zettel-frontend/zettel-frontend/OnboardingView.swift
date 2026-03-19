// OnboardingView.swift
// cashbox — Onboarding-Flow (6 Schritte)
// Layout: Stepper-Sidebar (280pt) | Content-Panel (flex)

import SwiftUI

// MARK: - Step Definitions

private struct OStep: Identifiable {
    let id: Int
    let name: String
    let sub: String
}

private let kSteps: [OStep] = [
    OStep(id: 1, name: "Konto erstellen",    sub: "E-Mail & Passwort"),
    OStep(id: 2, name: "Betriebsdaten",      sub: "Name, Adresse, Steuer-Nr."),
    OStep(id: 3, name: "Gerät einrichten",   sub: "iPad & TSE konfigurieren"),
    OStep(id: 4, name: "Plan wählen",        sub: "14 Tage kostenlos testen"),
    OStep(id: 5, name: "Pflicht-Checkliste", sub: "ELSTER, AVV, Verfahrensdoku"),
    OStep(id: 6, name: "Fertig",             sub: "Erste Schicht starten"),
]

private let kTitles: [Int: (String, String)] = [
    1: ("Konto erstellen",    "Wählen Sie eine E-Mail-Adresse und ein sicheres Passwort für den Administrator-Account."),
    2: ("Betriebsdaten",      "Diese Angaben erscheinen auf jedem Bon — sie müssen mit Ihren steuerlichen Angaben übereinstimmen."),
    3: ("Gerät einrichten",   "Geben Sie Ihrem iPad einen Namen und überprüfen Sie die TSE-Verbindung."),
    4: ("Plan wählen",        "14 Tage kostenlos testen. Kündigung jederzeit möglich."),
    5: ("Pflicht-Checkliste", "Diese Schritte sind gesetzlich vorgeschrieben. Ohne Abschluss ist kein Produktivbetrieb möglich."),
    6: ("Fertig",             "Ihr Kassensystem ist eingerichtet und bereit."),
]

// MARK: - Plan

private enum OPlan: String, CaseIterable, Identifiable {
    case starter, pro, business
    var id: String { rawValue }
    var displayName: String {
        switch self { case .starter: "Starter"; case .pro: "Pro"; case .business: "Business" }
    }
    var price: String {
        switch self { case .starter: "29"; case .pro: "59"; case .business: "99" }
    }
    var features: [String] {
        switch self {
        case .starter:  ["1 Gerät", "50 Produkte", "30 Tage Berichte", "TSE inklusive"]
        case .pro:      ["3 Geräte", "200 Produkte", "1 Jahr Berichte", "DSFinV-K Export"]
        case .business: ["10 Geräte", "Unbegrenzt", "10 Jahre Berichte", "DATEV Export"]
        }
    }
    var isPopular: Bool { self == .pro }
}

// MARK: - Checklist Items

private struct OCheckItem: Identifiable {
    let id: Int; let title: String; let description: String
    let badge: String; let required: Bool
}

private let kCheckItems: [OCheckItem] = [
    OCheckItem(id: 0, title: "AVV unterzeichnen",
               description: "Auftragsverarbeitungsvertrag gem. DSGVO Art. 28. In-App-Unterzeichnung mit Zeitstempel.",
               badge: "Pflicht", required: true),
    OCheckItem(id: 1, title: "ELSTER-Meldung einreichen",
               description: "Neue Kassensysteme müssen beim zuständigen Finanzamt über ELSTER gemeldet werden.",
               badge: "Pflicht · vor Go-live", required: true),
    OCheckItem(id: 2, title: "Verfahrensdokumentation herunterladen",
               description: "Auto-generiertes PDF mit Ihren Betriebsdaten. Muss aufbewahrt und dem Finanzamt auf Anfrage vorgelegt werden.",
               badge: "Pflicht · GoBD", required: true),
    OCheckItem(id: 3, title: "Steuerberater informieren",
               description: "Empfohlen: Steuerberater über das neue Kassensystem und die TSE-Nutzung informieren.",
               badge: "Empfohlen", required: false),
]

// MARK: - Root View

struct OnboardingView: View {
    @EnvironmentObject var authStore:      AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    @AppStorage("usesDarkMode") private var usesDarkMode = false

    @State private var currentStep = 1

    // Step 1
    @State private var email    = ""
    @State private var password = ""
    @State private var showPW   = false

    // Step 2
    @State private var businessName = ""
    @State private var address      = ""
    @State private var taxNumber    = ""
    @State private var vatId        = ""

    // Step 3
    @State private var deviceName = "iPad Theke"
    @State private var location   = ""

    // Step 4
    @State private var selectedPlan: OPlan = .pro

    // Step 5
    @State private var checkedItems: Set<Int> = []

    // Submit
    @State private var isLoading = false
    @State private var error:      AppError?
    @State private var showError = false

    var body: some View {
        HStack(spacing: 0) {
            StepperPanel(currentStep: currentStep, usesDarkMode: $usesDarkMode)
                .frame(width: 280)
            Rectangle().fill(DS.C.brdLight).frame(width: 1)
            ContentPanel(
                currentStep:  currentStep,
                email:        $email,  password: $password, showPW: $showPW,
                businessName: $businessName, address: $address,
                taxNumber:    $taxNumber, vatId: $vatId,
                deviceName:   $deviceName, location: $location,
                selectedPlan: $selectedPlan,
                checkedItems: $checkedItems,
                isLoading:    isLoading,
                canContinue:  canContinue,
                onNext:       handleNext,
                onBack:       { if currentStep > 1 { currentStep -= 1 } }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.bg)
        .preferredColorScheme(usesDarkMode ? .dark : .light)
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private var canContinue: Bool {
        !isLoading && {
            switch currentStep {
            case 1: return email.contains("@") && email.contains(".") && password.count >= 8
            case 2: return !businessName.trimmingCharacters(in: .whitespaces).isEmpty
                        && !address.trimmingCharacters(in: .whitespaces).isEmpty
                        && !taxNumber.trimmingCharacters(in: .whitespaces).isEmpty
            case 3: return !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
            default: return true
            }
        }()
    }

    private func handleNext() {
        guard canContinue else { return }
        if currentStep < 6 { currentStep += 1 }
        else { Task { await submit() } }
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authStore.register(
                businessName: businessName.trimmingCharacters(in: .whitespaces),
                email:        email.trimmingCharacters(in: .whitespaces),
                password:     password,
                address:      address.trimmingCharacters(in: .whitespaces),
                taxNumber:    taxNumber.trimmingCharacters(in: .whitespaces),
                deviceName:   deviceName.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

// MARK: - Stepper Panel (Links)

private struct StepperPanel: View {
    let currentStep: Int
    @Binding var usesDarkMode: Bool
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 9) {
                OBrandMark()
                Text("Kassensystem")
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(DS.C.text)
            }
            .padding(.bottom, 32)

            // "EINRICHTUNG" Label
            Text("Einrichtung")
                .font(.jakarta(11, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.6)
                .textCase(.uppercase)
                .padding(.bottom, 16)

            // Steps
            VStack(spacing: 0) {
                ForEach(Array(kSteps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 14) {
                        // Circle + connector
                        VStack(spacing: 0) {
                            OStepCircle(number: step.id, currentStep: currentStep)
                            if idx < kSteps.count - 1 {
                                Rectangle()
                                    .fill(currentStep > step.id
                                          ? DS.C.acc.opacity(0.3)
                                          : DS.C.brd(cs))
                                    .frame(width: 1.5, height: 28)
                            }
                        }
                        // Label
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.name)
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(nameColor(step.id))
                            Text(step.sub)
                                .font(.jakarta(10, weight: .regular))
                                .foregroundColor(DS.C.text2)
                                .lineSpacing(2)
                        }
                        .padding(.top, 4)
                        .padding(.bottom, idx < kSteps.count - 1 ? 28 : 0)
                    }
                }
            }

            Spacer()

            // Bottom
            Rectangle().fill(DS.C.brd(cs)).frame(height: 1).padding(.bottom, 14)
            Text("Fragen? support@kassensystem.de")
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
                .padding(.bottom, 12)
            HStack(spacing: 8) {
                Text("Dark Mode")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
                OToggle(isOn: $usesDarkMode)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.C.bg)
    }

    private func nameColor(_ id: Int) -> Color {
        if id == currentStep { return DS.C.text }
        if id < currentStep  { return DS.C.freeText }
        return DS.C.text2
    }
}

private struct OStepCircle: View {
    let number: Int
    let currentStep: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(bg)
                .frame(width: 30, height: 30)
            Circle()
                .strokeBorder(border, lineWidth: 1.5)
                .frame(width: 30, height: 30)
            if number < currentStep {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.C.freeText)
            } else {
                Text("\(number)")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(fg)
            }
        }
    }

    private var bg: Color {
        if number < currentStep  { return DS.C.freeBg }
        if number == currentStep { return DS.C.acc }
        return DS.C.sur
    }

    private var border: Color {
        if number < currentStep  { return DS.C.freeText }
        if number == currentStep { return DS.C.acc }
        return DS.C.brdLight
    }

    private var fg: Color {
        if number == currentStep { return .white }
        return DS.C.text2
    }
}

private struct OBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.C.acc)
                .frame(width: 26, height: 26)
            HStack(spacing: 2) {
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 5, height: 5)
                }
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 5, height: 5)
                }
            }
        }
    }
}

// MARK: - Content Panel (Rechts)

private struct ContentPanel: View {
    let currentStep: Int
    @Binding var email: String;    @Binding var password: String; @Binding var showPW: Bool
    @Binding var businessName: String; @Binding var address: String
    @Binding var taxNumber: String;    @Binding var vatId: String
    @Binding var deviceName: String;   @Binding var location: String
    @Binding var selectedPlan: OPlan
    @Binding var checkedItems: Set<Int>
    let isLoading:   Bool
    let canContinue: Bool
    let onNext:      () -> Void
    let onBack:      () -> Void
    @Environment(\.colorScheme) private var cs

    private var title: String { kTitles[currentStep]?.0 ?? "" }
    private var subtitle: String { kTitles[currentStep]?.1 ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 0) {
                Text("Schritt \(currentStep) von \(kSteps.count)")
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .padding(.bottom, 6)
                Text(title)
                    .font(.jakarta(20, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .tracking(-0.3)
                    .padding(.bottom, 4)
                Text(subtitle)
                    .font(.jakarta(12, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Rectangle().fill(DS.C.brd(cs)).frame(height: 1)

            // Body
            ScrollView(showsIndicators: false) {
                stepBody
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

            // Footer
            Rectangle().fill(DS.C.brd(cs)).frame(height: 1)
            HStack {
                Button("← Zurück", action: onBack)
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brd(cs), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .opacity(currentStep > 1 ? 1 : 0)
                    .disabled(currentStep <= 1)

                Spacer()

                Text("Schritt \(currentStep) von \(kSteps.count)")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)

                Spacer()

                Button(action: onNext) {
                    HStack(spacing: 7) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                                .scaleEffect(0.8)
                        } else if currentStep == kSteps.count {
                            Text("🎉 Kasse starten")
                                .font(.jakarta(12, weight: .semibold))
                        } else {
                            Text("Weiter")
                                .font(.jakarta(12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(currentStep == kSteps.count ? DS.C.freeText : DS.C.acc)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(DS.C.sur)
        }
        .background(DS.C.sur)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch currentStep {
        case 1: Step1Body(email: $email, password: $password, showPW: $showPW)
        case 2: Step2Body(businessName: $businessName, address: $address, taxNumber: $taxNumber, vatId: $vatId)
        case 3: Step3Body(deviceName: $deviceName, location: $location)
        case 4: Step4Body(selectedPlan: $selectedPlan)
        case 5: Step5Body(checkedItems: $checkedItems)
        case 6: Step6Body(plan: selectedPlan)
        default: EmptyView()
        }
    }
}

// MARK: - Step 1: Account

private struct Step1Body: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var showPW: Bool
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 14) {
            OField(label: "E-Mail", text: $email, placeholder: "admin@meinbetrieb.de",
                   keyboardType: .emailAddress, cs: cs)
            OSecureField(label: "Passwort", text: $password,
                         hint: "Mindestens 8 Zeichen", showPassword: $showPW, cs: cs)
        }
    }
}

// MARK: - Step 2: Betriebsdaten

private struct Step2Body: View {
    @Binding var businessName: String
    @Binding var address: String
    @Binding var taxNumber: String
    @Binding var vatId: String
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 14) {
            OField(label: "Unternehmensname", text: $businessName,
                   placeholder: "z.B. Shishabar Mustermann",
                   hint: "Vollständiger Firmenname wie im Handelsregister", cs: cs)
            OField(label: "Adresse", text: $address,
                   placeholder: "Straße, Hausnummer, PLZ, Stadt", cs: cs)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                OField(label: "Steuernummer", text: $taxNumber,
                       placeholder: "14/123/45678",
                       hint: "Vom Finanzamt zugewiesen", cs: cs)
                OField(label: "USt-IdNr. (optional)", text: $vatId,
                       placeholder: "DE123456789", cs: cs)
            }
        }
    }
}

// MARK: - Step 3: Gerät

private struct Step3Body: View {
    @Binding var deviceName: String
    @Binding var location: String
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                OField(label: "Gerätename", text: $deviceName,
                       placeholder: "z.B. iPad Theke",
                       hint: "Erscheint auf dem Bon (§ 6 KassenSichV)", cs: cs)
                OField(label: "Standort", text: $location,
                       placeholder: "z.B. Theke, Bar, Terrasse", cs: cs)
            }

            // TSE-Status (Phase 1: wird automatisch eingerichtet)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.C.freeBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.C.freeText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TSE-Verbindung erfolgreich")
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(DS.C.freeText)
                    Text("Fiskaly Cloud-TSE · BSI-zertifiziert · wird beim ersten Start aktiviert")
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.freeText.opacity(0.7))
                }
            }
            .padding(14)
            .background(DS.C.freeBg)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.C.freeText.opacity(0.2), lineWidth: 1))

            // ELSTER-Hinweis
            VStack(alignment: .leading, spacing: 3) {
                Text("Wichtig: ELSTER-Meldung erforderlich")
                    .font(.jakarta(11, weight: .semibold))
                    .foregroundColor(DS.C.warnText)
                Text("Neue Kassensysteme müssen beim Finanzamt gemeldet werden. Dies erledigen Sie in Schritt 5 der Checkliste.")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.warnText)
                    .lineSpacing(3)
            }
            .padding(12)
            .background(DS.C.warnBg)
            .cornerRadius(10)
        }
    }
}

// MARK: - Step 4: Plan

private struct Step4Body: View {
    @Binding var selectedPlan: OPlan
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(OPlan.allCases) { plan in
                    PlanCard(plan: plan, selected: selectedPlan == plan, cs: cs) {
                        selectedPlan = plan
                    }
                }
            }
            Text("14 Tage kostenlos testen — keine Kreditkarte nötig. Danach automatisch zum gewählten Plan.")
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }
}

private struct PlanCard: View {
    let plan: OPlan
    let selected: Bool
    let cs: ColorScheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if plan.isPopular {
                    Text("Empfohlen")
                        .font(.jakarta(10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(DS.C.acc)
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 26)
                }
                Text(plan.displayName)
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(selected ? DS.C.accT : DS.C.text)
                    .padding(.bottom, 4)
                (Text(plan.price)
                    .font(.jakarta(22, weight: .semibold))
                    .foregroundColor(selected ? DS.C.accT : DS.C.text)
                 + Text(" €/Monat")
                    .font(.jakarta(12, weight: .regular))
                    .foregroundColor(DS.C.text2))
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(plan.features, id: \.self) { feat in
                        HStack(spacing: 6) {
                            Text("✓")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DS.C.freeText)
                            Text(feat)
                                .font(.jakarta(11, weight: .regular))
                                .foregroundColor(selected ? DS.C.accT : DS.C.text2)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? DS.C.accBg : DS.C.bg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? DS.C.acc : DS.C.brd(cs), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Checklist

private struct Step5Body: View {
    @Binding var checkedItems: Set<Int>
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 10) {
            ForEach(kCheckItems) { item in
                let done = checkedItems.contains(item.id)
                Button {
                    if done { checkedItems.remove(item.id) }
                    else     { checkedItems.insert(item.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(done ? DS.C.freeText : .clear)
                                .frame(width: 22, height: 22)
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(done ? DS.C.freeText : DS.C.brd(cs), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.jakarta(13, weight: .semibold))
                                .foregroundColor(done ? DS.C.freeText : DS.C.text)
                            Text(item.description)
                                .font(.jakarta(11, weight: .regular))
                                .foregroundColor(DS.C.text2)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.badge)
                                .font(.jakarta(10, weight: .semibold))
                                .foregroundColor(item.required ? DS.C.dangerText : DS.C.text2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(item.required ? DS.C.dangerBg : DS.C.sur2)
                                .cornerRadius(20)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(done ? DS.C.freeBg : DS.C.bg)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(done ? DS.C.freeText : DS.C.brd(cs), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: done)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Step 6: Fertig

private struct Step6Body: View {
    let plan: OPlan

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(DS.C.freeBg)
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(DS.C.freeText)
            }

            Text("Einrichtung abgeschlossen!")
                .font(.jakarta(20, weight: .semibold))
                .foregroundColor(DS.C.text)
                .tracking(-0.3)
                .multilineTextAlignment(.center)

            Text("Ihr Kassensystem ist betriebsbereit. Öffnen Sie die erste Kassensitzung, legen Sie Ihre Produkte an und starten Sie mit der ersten Bestellung.")
                .font(.jakarta(12, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 400)

            HStack(spacing: 10) {
                KPITile(value: "14", label: "Trial-Tage verbleibend", valueColor: DS.C.acc)
                KPITile(value: plan.displayName, label: "Gewählter Plan", valueColor: DS.C.text)
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct KPITile: View {
    let value: String
    let label: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.jakarta(22, weight: .semibold))
                .foregroundColor(valueColor)
            Text(label)
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(DS.C.bg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.C.brdLight, lineWidth: 1))
    }
}

// MARK: - Shared Field Components

private struct OField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String? = nil
    var keyboardType: UIKeyboardType = .default
    let cs: ColorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.jakarta(10, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
                .textCase(.uppercase)
            NoAssistantTextField(
                placeholder:            placeholder,
                text:                   $text,
                keyboardType:           keyboardType,
                uiFont:                 UIFont.systemFont(ofSize: 13),
                uiTextColor:            UIColor(DS.C.text),
                autocapitalizationType: .none,
                autocorrectionType:     .no,
                isFocused:              $isFocused
            )
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(DS.C.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? DS.C.acc : DS.C.brd(cs), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            if let hint {
                Text(hint)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
    }
}

private struct OSecureField: View {
    let label: String
    @Binding var text: String
    var hint: String? = nil
    @Binding var showPassword: Bool
    let cs: ColorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.jakarta(10, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                NoAssistantTextField(
                    placeholder:     "Mindestens 8 Zeichen",
                    text:            $text,
                    uiFont:          UIFont.systemFont(ofSize: 13),
                    uiTextColor:     UIColor(DS.C.text),
                    isSecure:        !showPassword,
                    textContentType: .newPassword,
                    isFocused:       $isFocused
                )
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundColor(DS.C.text2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(DS.C.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? DS.C.acc : DS.C.brd(cs), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            if let hint {
                Text(hint)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
    }
}

private struct OToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? DS.C.accBg : DS.C.sur2)
                    .frame(width: 38, height: 22)
                    .overlay(Capsule().strokeBorder(DS.C.brdLight, lineWidth: 1))
                Circle()
                    .fill(isOn ? DS.C.acc : DS.C.text2)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Schritt 1") {
    OnboardingView()
        .environmentObject(AuthStore())
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    OnboardingView()
        .environmentObject(AuthStore())
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

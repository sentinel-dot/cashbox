// OnboardingView.swift
// cashbox — Onboarding-Flow (6 Schritte)
// Layout: Stepper-Sidebar (280pt) | Content-Panel (flex)
// Design v3: Success-Familie für erledigte Schritte, native Controls,
// Touch-Formulare (50pt), DS-Buttons.

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
    1: ("Konto erstellen",    "Wähle eine E-Mail-Adresse und ein sicheres Passwort für den Administrator-Account."),
    2: ("Betriebsdaten",      "Diese Angaben erscheinen auf jedem Bon — sie müssen mit deinen steuerlichen Angaben übereinstimmen."),
    3: ("Gerät einrichten",   "Gib deinem iPad einen Namen und überprüfe die TSE-Verbindung."),
    4: ("Plan wählen",        "14 Tage kostenlos testen. Kündigung jederzeit möglich."),
    5: ("Pflicht-Checkliste", "Diese Schritte sind gesetzlich vorgeschrieben. Ohne Abschluss ist kein Produktivbetrieb möglich."),
    6: ("Fertig",             "Dein Kassensystem ist eingerichtet und bereit."),
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
               description: "Auftragsverarbeitungsvertrag gem. DSGVO Art. 28 — erhältst du von cashbox per E-Mail zur Unterschrift.",
               badge: "Pflicht", required: true),
    OCheckItem(id: 1, title: "ELSTER-Meldung einreichen",
               description: "Neue Kassensysteme müssen beim zuständigen Finanzamt über ELSTER gemeldet werden.",
               badge: "Pflicht · vor Go-live", required: true),
    OCheckItem(id: 2, title: "Verfahrensdokumentation aufbewahren",
               description: "PDF mit deinen Betriebsdaten — wird dir vor dem Go-live bereitgestellt. Muss aufbewahrt und dem Finanzamt auf Anfrage vorgelegt werden.",
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

    @State private var currentStep = 1

    // Step 1
    @State private var email    = ""
    @State private var password = ""
    @State private var showPW   = false

    // Step 2
    @State private var businessName = ""
    @State private var address      = ""
    @State private var taxNumber    = ""

    // Step 3
    @State private var deviceName = "iPad Theke"

    // Step 4
    @State private var selectedPlan: OPlan = .pro

    // Step 5
    @State private var checkedItems: Set<Int> = []

    // Submit
    @State private var isLoading = false
    @State private var error:      AppError?
    @State private var showError = false

    // Abbrechen — mit Rückfrage, sobald etwas eingegeben wurde
    @State private var showCancelConfirm = false

    private var hasPartialInput: Bool {
        currentStep > 1 || !email.isEmpty || !password.isEmpty
            || !businessName.isEmpty || !address.isEmpty || !taxNumber.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            StepperPanel(currentStep: currentStep)
                .frame(width: 280)
            Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)
            ContentPanel(
                currentStep:  currentStep,
                email:        $email,  password: $password, showPW: $showPW,
                businessName: $businessName, address: $address,
                taxNumber:    $taxNumber,
                deviceName:   $deviceName,
                selectedPlan: $selectedPlan,
                checkedItems: $checkedItems,
                isLoading:    isLoading,
                canContinue:  canContinue,
                onNext:       handleNext,
                onBack:       { if currentStep > 1 { currentStep -= 1 } },
                onCancel:     {
                    if hasPartialInput { showCancelConfirm = true } else { dismiss() }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.bg)
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
        .confirmationDialog(
            "Einrichtung abbrechen?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Abbrechen und Eingaben verwerfen", role: .destructive) { dismiss() }
            Button("Weiter einrichten", role: .cancel) {}
        } message: {
            Text("Deine bisherigen Eingaben gehen verloren.")
        }
    }

    private var emailIsValid: Bool {
        email.trimmingCharacters(in: .whitespaces)
            .range(of: #"^\S+@\S+\.\S{2,}$"#, options: .regularExpression) != nil
    }

    private var canContinue: Bool {
        !isLoading && {
            switch currentStep {
            case 1: return emailIsValid && password.count >= 8
            case 2: return !businessName.trimmingCharacters(in: .whitespaces).isEmpty
                        && !address.trimmingCharacters(in: .whitespaces).isEmpty
                        && !taxNumber.trimmingCharacters(in: .whitespaces).isEmpty
            case 3: return !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
            // Pflicht-Checkliste ist Pflicht — Copy und Verhalten decken sich
            case 5: return kCheckItems.filter(\.required).allSatisfy { checkedItems.contains($0.id) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                AppBrandMark(size: 28)
                Text("cashbox")
                    .dsFont(.raw(17, weight: .bold))
                    .foregroundColor(DS.C.text)
            }
            .padding(.bottom, 32)

            DSSectionLabel(text: "Einrichtung")
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
                                          ? DS.C.acc.opacity(0.35)
                                          : DS.C.brdAdaptive)
                                    .frame(width: 1.5, height: 28)
                            }
                        }
                        // Label
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.name)
                                .dsFont(.raw(15, weight: .semibold))
                                .foregroundColor(nameColor(step.id))
                            Text(step.sub)
                                .dsFont(.caption)
                                .foregroundColor(DS.C.text2)
                        }
                        .padding(.top, 5)
                        .padding(.bottom, idx < kSteps.count - 1 ? 26 : 0)
                    }
                }
            }

            Spacer()

            // Bottom
            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1).padding(.bottom, 14)
            Text("Fragen? support@cashbox.de")
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .padding(DS.S.pagePad)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.C.bg)
    }

    private func nameColor(_ id: Int) -> Color {
        if id == currentStep { return DS.C.text }
        if id < currentStep  { return DS.C.accT }
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
                .frame(width: 32, height: 32)
            Circle()
                .strokeBorder(border, lineWidth: 1.5)
                .frame(width: 32, height: 32)
            if number < currentStep {
                Image(systemName: "checkmark")
                    .dsFont(.raw(11, weight: .bold))
                    .foregroundColor(DS.C.accT)
            } else {
                Text("\(number)")
                    .dsFont(.raw(14, weight: .semibold), monoDigits: true)
                    .foregroundColor(fg)
            }
        }
    }

    private var bg: Color {
        if number < currentStep  { return DS.C.accBg }
        if number == currentStep { return DS.C.acc }
        return DS.C.sur
    }

    private var border: Color {
        if number < currentStep  { return DS.C.acc.opacity(0.4) }
        if number == currentStep { return DS.C.acc }
        return DS.C.brdAdaptive
    }

    private var fg: Color {
        if number == currentStep { return .white }
        return DS.C.text2
    }
}

// MARK: - Content Panel (Rechts)

private struct ContentPanel: View {
    let currentStep: Int
    @Binding var email: String;    @Binding var password: String; @Binding var showPW: Bool
    @Binding var businessName: String; @Binding var address: String
    @Binding var taxNumber: String
    @Binding var deviceName: String
    @Binding var selectedPlan: OPlan
    @Binding var checkedItems: Set<Int>
    let isLoading:   Bool
    let canContinue: Bool
    let onNext:      () -> Void
    let onBack:      () -> Void
    let onCancel:    () -> Void

    private var title: String { kTitles[currentStep]?.0 ?? "" }
    private var subtitle: String { kTitles[currentStep]?.1 ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Schritt \(currentStep) von \(kSteps.count)")
                        .dsFont(.caption, monoDigits: true)
                        .foregroundColor(DS.C.text2)
                    Text(title)
                        .dsFont(.title)
                        .foregroundColor(DS.C.text)
                    Text(subtitle)
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .dsFont(.icon(13, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DS.C.sur2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einrichtung abbrechen")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

            // Body
            ScrollView(showsIndicators: false) {
                stepBody
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

            // Footer
            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
            HStack {
                if currentStep > 1 {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .dsFont(.icon(13, weight: .semibold))
                            Text("Zurück")
                        }
                    }
                    .buttonStyle(DSSecondaryButton(height: 46, fullWidth: false))
                }

                Spacer()

                Button(action: onNext) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else if currentStep == kSteps.count {
                            Image(systemName: "checkmark")
                                .dsFont(.raw(14, weight: .semibold))
                            Text("Kasse starten")
                        } else {
                            Text("Weiter")
                            Image(systemName: "chevron.right")
                                .dsFont(.raw(13, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 46, fullWidth: false))
                .disabled(!canContinue)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(DS.C.sur)
        }
        .background(DS.C.sur)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch currentStep {
        case 1: Step1Body(email: $email, password: $password, showPW: $showPW)
        case 2: Step2Body(businessName: $businessName, address: $address, taxNumber: $taxNumber)
        case 3: Step3Body(deviceName: $deviceName)
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

    var body: some View {
        VStack(spacing: 16) {
            OField(label: "E-Mail", text: $email, placeholder: "admin@meinbetrieb.de",
                   keyboardType: .emailAddress)
            OSecureField(label: "Passwort", text: $password,
                         hint: "Mindestens 8 Zeichen", showPassword: $showPW)
        }
    }
}

// MARK: - Step 2: Betriebsdaten

private struct Step2Body: View {
    @Binding var businessName: String
    @Binding var address: String
    @Binding var taxNumber: String

    var body: some View {
        VStack(spacing: 16) {
            OField(label: "Unternehmensname", text: $businessName,
                   placeholder: "z.B. Shishabar Mustermann",
                   hint: "Vollständiger Firmenname wie im Handelsregister")
            OField(label: "Adresse", text: $address,
                   placeholder: "Straße, Hausnummer, PLZ, Stadt")
            OField(label: "Steuernummer oder USt-IdNr.", text: $taxNumber,
                   placeholder: "14/123/45678",
                   hint: "Vom Finanzamt zugewiesen — erscheint auf jedem Bon")
        }
    }
}

// MARK: - Step 3: Gerät

private struct Step3Body: View {
    @Binding var deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OField(label: "Gerätename", text: $deviceName,
                   placeholder: "z.B. iPad Theke",
                   hint: "Erscheint auf dem Bon (§ 6 KassenSichV)")

            // TSE-Status — ehrlich: die Anbindung existiert noch nicht (Phase 2),
            // hier wird kein Erfolg vorgetäuscht.
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.C.brassBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: "clock")
                        .dsFont(.icon(15, weight: .semibold))
                        .foregroundColor(DS.C.brassText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TSE-Anbindung folgt vor dem Go-live")
                        .dsFont(.subBold)
                        .foregroundColor(DS.C.brassText)
                    Text("Fiskaly Cloud-TSE · BSI-zertifiziert · wird vor dem Produktivbetrieb aktiviert")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.brassText.opacity(0.85))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.brassBg.opacity(0.6)))

            // ELSTER-Hinweis
            VStack(alignment: .leading, spacing: 4) {
                Text("Wichtig: ELSTER-Meldung erforderlich")
                    .dsFont(.subBold)
                    .foregroundColor(DS.C.brassText)
                Text("Neue Kassensysteme müssen beim Finanzamt gemeldet werden. Das erledigst du in Schritt 5 der Checkliste.")
                    .dsFont(.sub)
                    .foregroundColor(DS.C.brassText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.brassBg))
        }
    }
}

// MARK: - Step 4: Plan

private struct Step4Body: View {
    @Binding var selectedPlan: OPlan

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(OPlan.allCases) { plan in
                    PlanCard(plan: plan, selected: selectedPlan == plan) {
                        selectedPlan = plan
                    }
                }
            }
            Text("14 Tage kostenlos testen — keine Kreditkarte nötig. Danach automatisch zum gewählten Plan.")
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }
}

private struct PlanCard: View {
    let plan: OPlan
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if plan.isPopular {
                    Text("Empfohlen")
                        .dsFont(.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.C.acc))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 12)
                } else {
                    Spacer().frame(height: 32)
                }
                Text(plan.displayName)
                    .dsFont(.raw(17, weight: .bold))
                    .foregroundColor(selected ? DS.C.accT : DS.C.text)
                    .padding(.bottom, 4)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(plan.price)
                        .dsFont(.money(26, weight: .bold))
                        .foregroundColor(selected ? DS.C.accT : DS.C.text)
                    Text("€/Monat")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
                .padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(plan.features, id: \.self) { feat in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .dsFont(.raw(11, weight: .bold))
                                .foregroundColor(DS.C.accT)
                            Text(feat)
                                .dsFont(.sub)
                                .foregroundColor(selected ? DS.C.text : DS.C.text2)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .fill(selected ? DS.C.accBg : DS.C.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(selected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
            .animation(DS.M.fast, value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5: Checklist

private struct Step5Body: View {
    @Binding var checkedItems: Set<Int>

    var body: some View {
        VStack(spacing: 10) {
            ForEach(kCheckItems) { item in
                let done = checkedItems.contains(item.id)
                Button {
                    if done { checkedItems.remove(item.id) }
                    else     { checkedItems.insert(item.id) }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(done ? DS.C.acc : .clear)
                                .frame(width: 24, height: 24)
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(done ? DS.C.acc : DS.C.brdAdaptive, lineWidth: 1.5)
                                .frame(width: 24, height: 24)
                            if done {
                                Image(systemName: "checkmark")
                                    .dsFont(.raw(11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .dsFont(.bodyBold)
                                .foregroundColor(done ? DS.C.accT : DS.C.text)
                            Text(item.description)
                                .dsFont(.sub)
                                .foregroundColor(DS.C.text2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.badge)
                                .dsFont(.captionBold)
                                .foregroundColor(item.required ? DS.C.brassText : DS.C.text2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(item.required ? DS.C.brassBg : DS.C.sur2))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.R.card)
                            .fill(done ? DS.C.accBg : DS.C.bg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.card)
                            .strokeBorder(done ? DS.C.acc : DS.C.brdAdaptive, lineWidth: done ? 1.5 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
                    .animation(DS.M.fast, value: done)
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
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(DS.C.successBg)
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark")
                    .dsFont(.raw(32, weight: .bold))
                    .foregroundColor(DS.C.successText)
            }

            Text("Einrichtung abgeschlossen!")
                .dsFont(.title)
                .foregroundColor(DS.C.text)
                .multilineTextAlignment(.center)

            Text("Dein Kassensystem ist betriebsbereit. Öffne die erste Kassensitzung, lege deine Produkte an und starte mit der ersten Bestellung.")
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                KPITile(value: "14", label: "Trial-Tage verbleibend", valueColor: DS.C.accT)
                KPITile(value: plan.displayName, label: "Gewählter Plan", valueColor: DS.C.text)
            }
            .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct KPITile: View {
    let value: String
    let label: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .dsFont(.raw(24, weight: .bold), monoDigits: true)
                .foregroundColor(valueColor)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.bg))
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

// MARK: - Shared Field Components

// Dünner Alias auf DSTextField (eine Feld-Quelle app-weit)
private struct OField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String? = nil
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        DSTextField(label: label, placeholder: placeholder, text: $text,
                    keyboard: keyboardType, hint: hint)
    }
}

private struct OSecureField: View {
    let label: String
    @Binding var text: String
    var hint: String? = nil
    @Binding var showPassword: Bool   // Alt-API — Reveal übernimmt DSTextField intern

    var body: some View {
        DSTextField(label: label, placeholder: "Mindestens 8 Zeichen", text: $text,
                    isSecure: true, contentType: .newPassword, hint: hint)
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

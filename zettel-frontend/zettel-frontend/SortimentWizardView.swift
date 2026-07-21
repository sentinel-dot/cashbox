// SortimentWizardView.swift — S17B: Starter-Sortiment-Wizard (Spec §9, 8 Schritte).
// Muster wie OnboardingView: StepperPanel links, Inhalt rechts, aller State im Root.
// Paket → Auswahl → Namen & Preise → MwSt. prüfen → Visuals → Vorschau → Import → Ergebnis.
// Import ist idempotent: Ein UUID-Key wird beim Betreten von Schritt 7 EINMAL erzeugt;
// jeder Retry nutzt denselben Key — Doppeltap/Timeout erzeugt nie Duplikate.

import SwiftUI

// MARK: - Schritte

private struct WStep { let number: Int; let title: String }

private let kWizardSteps: [WStep] = [
    WStep(number: 1, title: "Paket wählen"),
    WStep(number: 2, title: "Auswahl anpassen"),
    WStep(number: 3, title: "Namen & Preise"),
    WStep(number: 4, title: "MwSt. prüfen"),
    WStep(number: 5, title: "Visuals"),
    WStep(number: 6, title: "Vorschau"),
    WStep(number: 7, title: "Import"),
    WStep(number: 8, title: "Fertig"),
]

// MARK: - Root

struct SortimentWizardView: View {
    @EnvironmentObject var productStore: ProductStore
    @Environment(\.dismiss) private var dismiss

    // Daten
    @State private var presets: [AssortmentPreset] = []
    @State private var loadFailed = false

    // Wizard-State (alles im Root — Zurück bewahrt Eingaben)
    @State private var currentStep = 1
    @State private var selectedPreset: AssortmentPreset? = nil
    @State private var selectedKeys:  Set<String> = []
    @State private var names:  [String: String] = [:]
    @State private var prices: [String: String] = [:]
    @State private var reviewState = WizardReviewState()
    @State private var chosenVisuals: [String: String?] = [:]   // itemKey → explizite Wahl
    @State private var manualVisuals: Set<String> = []          // nie automatisch überschreiben
    @State private var visualPickerItem: String? = nil          // itemKey im Picker

    // Import
    @State private var idempotencyKey: String? = nil
    @State private var isImporting = false
    @State private var importResult: PresetImportResult? = nil
    @State private var importError: AppError? = nil
    @State private var showAbortConfirm = false

    private var isDirty: Bool { selectedPreset != nil && importResult == nil }

    var body: some View {
        HStack(spacing: 0) {
            stepperPanel
                .frame(width: 280)
                .background(DS.C.sur)
                .overlay(Rectangle().frame(width: 1).foregroundColor(DS.C.brdAdaptive), alignment: .trailing)

            VStack(spacing: 0) {
                contentHeader
                stepBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .background(DS.C.bg)
        }
        .task { await loadPresets() }
        .confirmationDialog("Einrichtung verlassen?", isPresented: $showAbortConfirm, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { dismiss() }
            Button("Weiter einrichten", role: .cancel) {}
        } message: {
            Text("Deine Auswahl und Preise gehen verloren. Bereits importierte Produkte bleiben erhalten.")
        }
        .sheet(isPresented: Binding(
            get: { visualPickerItem != nil },
            set: { if !$0 { visualPickerItem = nil } }
        )) {
            if let itemKey = visualPickerItem {
                VisualPickerSheet(
                    selectedKey: effectiveVisual(for: itemKey),
                    onSelect: { key in
                        chosenVisuals[itemKey] = key
                        manualVisuals.insert(itemKey)
                        visualPickerItem = nil
                    }
                )
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text((importError?.localizedDescription ?? "Unbekannter Fehler")
                 + "\nDein Fortschritt bleibt erhalten — „Jetzt importieren“ versucht es sicher erneut.")
        }
    }

    // MARK: Stepper (links)

    private var stepperPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(DS.C.accBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: "shippingbox")
                        .dsFont(.raw(15, weight: .semibold))
                        .foregroundColor(DS.C.accT)
                }
                Text("Starter-Sortiment")
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(kWizardSteps, id: \.number) { step in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(step.number < currentStep ? DS.C.acc
                                      : step.number == currentStep ? DS.C.accBg : Color.clear)
                                .overlay(Circle().strokeBorder(
                                    step.number <= currentStep ? DS.C.acc : DS.C.brdAdaptive, lineWidth: 1.5))
                                .frame(width: 28, height: 28)
                            if step.number < currentStep {
                                Image(systemName: "checkmark")
                                    .dsFont(.raw(11, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text("\(step.number)")
                                    .dsFont(.raw(13, weight: .semibold), monoDigits: true)
                                    .foregroundColor(step.number == currentStep ? DS.C.accT : DS.C.text2)
                            }
                        }
                        Text(step.title)
                            .dsFont(.raw(15, weight: step.number == currentStep ? .semibold : .regular))
                            .foregroundColor(step.number == currentStep ? DS.C.text : DS.C.text2)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                }
            }

            Spacer()
        }
    }

    // MARK: Header + Footer

    private var contentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kWizardSteps[currentStep - 1].title)
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
                Text(headerSubtitle)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            Button {
                if isDirty { showAbortConfirm = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .dsFont(.raw(13, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.C.sur2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Einrichtung schließen")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }

    private var headerSubtitle: String {
        switch currentStep {
        case 1: return "Womit startet dein Betrieb?"
        case 2: return "Alles Ausgewählte wird importiert — Vorlagen und Pfand sind gesondert markiert"
        case 3: return "Preise sind Pflicht — 0,00 € gibt es nicht"
        case 4: return "Vorschläge, keine Steuerberatung — bitte ausdrücklich bestätigen"
        case 5: return "Symbole sind optional — „Ohne Symbol“ ist gleichwertig"
        case 6: return "Genau so erscheint dein Sortiment an der Kasse"
        case 7: return "Ein Tipper genügt — Doppeltap und Wiederholung sind sicher"
        default: return "Dein Sortiment ist bereit"
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if currentStep > 1 && currentStep < 8 {
                Button("Zurück") { currentStep -= 1 }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))
                    .disabled(isImporting)
            }
            Spacer()
            if currentStep < 7 {
                Button("Weiter") { goNext() }
                    .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                    .disabled(!canContinue)
            } else if currentStep == 7 {
                Button {
                    Task { await runImport() }
                } label: {
                    if isImporting {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Jetzt importieren")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(isImporting)
            } else {
                Button("Sortiment öffnen") { dismiss() }
                    .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
    }

    // MARK: Navigation + Validierung

    private var selectedProducts: [PresetProduct] {
        guard let preset = selectedPreset else { return [] }
        return preset.products.filter { selectedKeys.contains($0.itemKey) }
    }

    private var canContinue: Bool {
        switch currentStep {
        case 1: return selectedPreset != nil
        case 2: return !selectedKeys.isEmpty && templatesValid
        case 3: return namesAndPricesValid
        case 4: return reviewState.allConfirmed(selected: selectedProducts)
        default: return true
        }
    }

    private var templatesValid: Bool {
        selectedProducts.filter(\.isTemplate).allSatisfy { item in
            let name = (names[item.itemKey] ?? "").trimmingCharacters(in: .whitespaces)
            return !name.isEmpty && name != item.nameDe && (parseCents(prices[item.itemKey] ?? "") ?? 0) > 0
        }
    }

    private var namesAndPricesValid: Bool {
        selectedProducts.allSatisfy { item in
            let name = (names[item.itemKey] ?? "").trimmingCharacters(in: .whitespaces)
            return !name.isEmpty && (parseCents(prices[item.itemKey] ?? "") ?? 0) > 0
        }
    }

    private func goNext() {
        if currentStep == 6 && idempotencyKey == nil {
            // Ein Key pro Import-Versuch-Serie — Retry nutzt denselben
            idempotencyKey = UUID().uuidString.lowercased()
        }
        currentStep += 1
    }

    private func selectPreset(_ preset: AssortmentPreset) {
        selectedPreset = preset
        // Alles vorausgewählt außer Vorlagen und Pfand-gesperrten Zeilen (§9.2)
        selectedKeys = Set(preset.readyProducts.map(\.itemKey))
        names = Dictionary(uniqueKeysWithValues: preset.products.map { ($0.itemKey, $0.nameDe) })
        prices = [:]
        reviewState = WizardReviewState()
        chosenVisuals = [:]
        manualVisuals = []
        importResult = nil
        idempotencyKey = nil
    }

    /// Effektives Visual: manuelle Wahl > kuratiertes Preset-Visual > Namensheuristik
    private func effectiveVisual(for itemKey: String) -> String? {
        if manualVisuals.contains(itemKey), let chosen = chosenVisuals[itemKey] { return chosen }
        guard let def = selectedPreset?.products.first(where: { $0.itemKey == itemKey }) else { return nil }
        if let curated = def.visualKey { return curated }
        return suggestedVisualKey(
            forName: names[itemKey] ?? def.nameDe,
            categoryName: selectedPreset?.categories.first { $0.categoryKey == def.categoryKey }?.nameDe
        )
    }

    // MARK: Import

    private func runImport() async {
        guard let preset = selectedPreset, let key = idempotencyKey, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let items: [PresetImportItem] = selectedProducts.map { def in
            PresetImportItem(
                itemKey:         def.itemKey,
                name:            (names[def.itemKey] ?? def.nameDe).trimmingCharacters(in: .whitespaces),
                priceCents:      parseCents(prices[def.itemKey] ?? "") ?? 0,
                vatRateInhouse:  def.vatRateInhouse,
                vatRateTakeaway: def.vatRateTakeaway,
                visualKey:       effectiveVisual(for: def.itemKey),
                reviewConfirmed: def.needsIndividualReview ? true : nil,
                onNameCollision: nil
            )
        }
        let body = PresetImportBody(
            presetId:        preset.presetId,
            presetVersion:   preset.version,
            taxBasisVersion: preset.taxBasisVersion,
            vatConfirmed:    true,
            items:           items
        )

        do {
            importResult = try await productStore.importPreset(body, idempotencyKey: key)
            Haptics.success()
            currentStep = 8
        } catch let e as AppError {
            importError = e
            Haptics.error()
        } catch {
            importError = .unknown(error.localizedDescription)
            Haptics.error()
        }
    }

    // MARK: Laden

    private func loadPresets() async {
        guard presets.isEmpty else { return }
        do {
            presets = try await productStore.loadPresets()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    // MARK: Step Bodies

    @ViewBuilder
    private var stepBody: some View {
        switch currentStep {
        case 1:  step1PaketWaehlen
        case 2:  step2Auswahl
        case 3:  step3NamenPreise
        case 4:  step4MwSt
        case 5:  step5Visuals
        case 6:  step6Vorschau
        case 7:  step7Import
        default: step8Ergebnis
        }
    }

    // ── Schritt 1: Paket wählen ──

    private var step1PaketWaehlen: some View {
        ScrollView(showsIndicators: false) {
            if loadFailed {
                DSEmptyState(
                    icon: "wifi.slash",
                    title: "Pakete nicht geladen",
                    message: "Die Starter-Pakete konnten nicht geladen werden.",
                    actionLabel: "Erneut versuchen",
                    action: { Task { presets = []; await loadPresets() } }
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(presets) { preset in
                        PresetCard(
                            preset:     preset,
                            isSelected: selectedPreset?.presetId == preset.presetId,
                            onTap:      { selectPreset(preset) }
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    // ── Schritt 2: Auswahl ──

    private var step2Auswahl: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let preset = selectedPreset {
                    ForEach(preset.categories) { cat in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: cat.color)).frame(width: 10, height: 10)
                                DSSectionLabel(text: cat.nameDe)
                            }
                            ForEach(preset.products.filter { $0.categoryKey == cat.categoryKey }) { item in
                                SelectRow(
                                    item:       item,
                                    isSelected: selectedKeys.contains(item.itemKey),
                                    name:       nameBinding(item),
                                    price:      priceBinding(item),
                                    onToggle:   { toggleSelection(item) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func toggleSelection(_ item: PresetProduct) {
        if item.isDepositBlocked { return }   // UI-Sperre; der Server lehnt zusätzlich ab
        if selectedKeys.contains(item.itemKey) {
            selectedKeys.remove(item.itemKey)
        } else {
            selectedKeys.insert(item.itemKey)
        }
    }

    private func nameBinding(_ item: PresetProduct) -> Binding<String> {
        Binding(
            get: { names[item.itemKey] ?? item.nameDe },
            set: { names[item.itemKey] = $0 }
        )
    }

    private func priceBinding(_ item: PresetProduct) -> Binding<String> {
        Binding(
            get: { prices[item.itemKey] ?? "" },
            set: { prices[item.itemKey] = $0 }
        )
    }

    // ── Schritt 3: Namen & Preise ──

    private var step3NamenPreise: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(selectedProducts) { item in
                    PriceRow(
                        item:  item,
                        name:  Binding(
                            get: { names[item.itemKey] ?? item.nameDe },
                            set: { names[item.itemKey] = $0 }
                        ),
                        price: Binding(
                            get: { prices[item.itemKey] ?? "" },
                            set: { prices[item.itemKey] = $0 }
                        )
                    )
                }
            }
            .padding(24)
        }
    }

    // ── Schritt 4: MwSt. prüfen ──

    private var step4MwSt: some View {
        let standard = selectedProducts.filter { !$0.needsIndividualReview }
        let food     = standard.filter { $0.vatRateInhouse == "7" }
        let regular  = standard.filter { $0.vatRateInhouse != "7" }
        let review   = selectedProducts.filter(\.needsIndividualReview)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if !food.isEmpty {
                    VatGroupCard(title: "Speisen · 7 %", items: food.map { names[$0.itemKey] ?? $0.nameDe })
                }
                if !regular.isEmpty {
                    VatGroupCard(title: "Getränke & Sonstiges · 19 %", items: regular.map { names[$0.itemKey] ?? $0.nameDe })
                }

                if !standard.isEmpty {
                    Toggle(isOn: $reviewState.bulkConfirmed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sätze geprüft")
                                .dsFont(.subBold)
                                .foregroundColor(DS.C.text)
                            Text("Die vorgeschlagenen Umsatzsteuersätze für die Zeilen oben sind für unseren Betrieb plausibel.")
                                .dsFont(.caption)
                                .foregroundColor(DS.C.text2)
                        }
                    }
                    .tint(DS.C.acc)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.sur))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                }

                if !review.isEmpty {
                    DSSectionLabel(text: "Einzeln zu bestätigen")
                    ForEach(review) { item in
                        ReviewRow(
                            item:        item,
                            displayName: names[item.itemKey] ?? item.nameDe,
                            isConfirmed: reviewState.individuallyConfirmed.contains(item.itemKey),
                            onConfirm:   { confirmed in
                                if confirmed {
                                    reviewState.confirmIndividually(item.itemKey)
                                } else {
                                    reviewState.individuallyConfirmed.remove(item.itemKey)
                                }
                            }
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    // ── Schritt 5: Visuals ──

    private var step5Visuals: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(selectedProducts.enumerated()), id: \.element.itemKey) { idx, item in
                    ProductCard(product: previewProduct(item, id: idx + 1)) {
                        visualPickerItem = item.itemKey
                    }
                    .accessibilityLabel("\(names[item.itemKey] ?? item.nameDe), Symbol: \(ProduktVisualCatalog.label(for: effectiveVisual(for: item.itemKey)))")
                    .accessibilityHint("Doppeltippen, um das Symbol zu ändern")
                }
            }
            .padding(24)
        }
    }

    // ── Schritt 6: Vorschau ──

    private var step6Vorschau: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let preset = selectedPreset {
                    summaryBanner

                    ForEach(preset.categories) { cat in
                        let items = selectedProducts
                            .filter { $0.categoryKey == cat.categoryKey }
                            .sorted { $0.sortOrder < $1.sortOrder }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: cat.color)).frame(width: 10, height: 10)
                                    DSSectionLabel(text: cat.nameDe)
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                    ForEach(Array(items.enumerated()), id: \.element.itemKey) { idx, item in
                                        ProductCard(product: previewProduct(item, id: idx + 1)) {}
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var summaryBanner: some View {
        let blocked = (selectedPreset?.products ?? []).filter(\.isDepositBlocked).count
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedProducts.count) Produkte in \(usedCategoryCount) Kategorien")
                    .dsFont(.subBold)
                    .foregroundColor(DS.C.text)
                if blocked > 0 {
                    Text("\(blocked) pfandpflichtige Artikel bleiben gesperrt, bis die Pfandfunktion verfügbar ist.")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.brassText)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.sur))
        .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }

    private var usedCategoryCount: Int {
        Set(selectedProducts.map(\.categoryKey)).count
    }

    private func previewProduct(_ item: PresetProduct, id: Int) -> Product {
        let catDef = selectedPreset?.categories.first { $0.categoryKey == item.categoryKey }
        let cat = catDef.map {
            ProductCategoryRef(id: id, name: $0.nameDe, color: $0.color, sortOrder: $0.sortOrder)
        }
        return Product(
            id: id,
            name: names[item.itemKey] ?? item.nameDe,
            priceCents: parseCents(prices[item.itemKey] ?? "") ?? 0,
            vatRateInhouse: item.vatRateInhouse,
            vatRateTakeaway: item.vatRateTakeaway,
            isActive: true,
            sortOrder: item.sortOrder,
            visualKey: effectiveVisual(for: item.itemKey),
            createdAt: "",
            category: cat,
            modifierGroups: []
        )
    }

    // ── Schritt 7: Import ──

    private var step7Import: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .dsFont(.icon(44, weight: .light))
                .foregroundColor(DS.C.accT)
            Text("\(selectedProducts.count) Produkte importieren")
                .dsFont(.title)
                .foregroundColor(DS.C.text)
            Text("Alle Sätze sind bestätigt, jeder Preis ist geprüft.\nDer Import ist gegen Doppeltap und Verbindungsabbrüche abgesichert.")
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // ── Schritt 8: Ergebnis ──

    private var step8Ergebnis: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                DSSuccessCheckmark(size: 64)
                Text("Sortiment eingerichtet")
                    .dsFont(.title)
                    .foregroundColor(DS.C.text)

                if let result = importResult {
                    VStack(alignment: .leading, spacing: 12) {
                        ResultLine(icon: "checkmark.circle.fill", tint: DS.C.accT,
                                   text: "\(result.imported.products) Produkte und \(result.imported.categories) Kategorien importiert")
                        if !result.skipped.isEmpty {
                            ResultLine(icon: "arrow.uturn.forward.circle", tint: DS.C.text2,
                                       text: "\(result.skipped.count) übersprungen (bereits vorhanden oder Namenskonflikt)")
                        }
                        let blocked = (selectedPreset?.products ?? []).filter(\.isDepositBlocked).count
                        if blocked > 0 {
                            ResultLine(icon: "lock.circle", tint: DS.C.brassText,
                                       text: "\(blocked) pfandpflichtige Artikel gesperrt bis zur Pfandfunktion")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 520)
                    .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.sur))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(24)
        }
    }
}

// MARK: - Bausteine

private struct PresetCard: View {
    let preset:     AssortmentPreset
    let isSelected: Bool
    let onTap:      () -> Void

    private var subtitle: String {
        if preset.products.isEmpty { return "Ohne Vorlagen beginnen" }
        let ready = preset.readyProducts.count
        return "\(preset.categories.count) Kategorien · \(ready) Produkte sofort startklar"
    }

    private var depositNote: String? {
        let blocked = preset.products.filter(\.isDepositBlocked).count
        guard blocked > 0 else { return nil }
        return "\(blocked) Pfand-Artikel folgen mit der Pfandfunktion"
    }

    private var icon: String {
        switch preset.presetId {
        case "shisha_bar": return "flame"
        case "cafe":       return "cup.and.saucer"
        case "spaeti":     return "basket"
        default:            return "square.dashed"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .dsFont(.raw(22, weight: .medium))
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .dsFont(.raw(20))
                            .foregroundColor(DS.C.acc)
                    }
                }
                Text(preset.displayName)
                    .dsFont(.raw(18, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text(subtitle)
                    .dsFont(.sub)
                    .foregroundColor(DS.C.text2)
                if let note = depositNote {
                    Text(note)
                        .dsFont(.caption)
                        .foregroundColor(DS.C.brassText)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(isSelected ? DS.C.accBg : DS.C.sur))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(isSelected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(DS.M.fast, value: isSelected)
    }
}

private struct SelectRow: View {
    let item:       PresetProduct
    let isSelected: Bool
    @Binding var name:  String
    @Binding var price: String
    let onToggle:   () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: item.isDepositBlocked ? "lock.fill"
                          : isSelected ? "checkmark.square.fill" : "square")
                        .dsFont(.raw(19))
                        .foregroundColor(item.isDepositBlocked ? DS.C.text2 : isSelected ? DS.C.acc : DS.C.text2)

                    Text(item.nameDe)
                        .dsFont(.raw(15, weight: .medium))
                        .foregroundColor(item.isDepositBlocked ? DS.C.text2 : DS.C.text)

                    if item.isDepositBlocked {
                        DSPill(label: "Pfandfunktion erforderlich", fg: DS.C.brassText, bg: DS.C.brassBg)
                    } else if item.isTemplate {
                        DSPill(label: "Vorlage", fg: DS.C.brassText, bg: DS.C.brassBg)
                    } else if item.needsIndividualReview {
                        DSPill(label: "Satz prüfen", fg: DS.C.brassText, bg: DS.C.brassBg)
                    }
                    Spacer()
                    Text("\(item.vatRateInhouse) %")
                        .dsFont(.mono(12, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.isDepositBlocked)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            // §5.3: Vorlage erst mit konkretem Namen + aufgedrucktem Preis brauchbar
            if item.isTemplate && isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    DSTextField(label: "Konkreter Produktname", placeholder: "[Marke] [Variante], [Menge]",
                                text: $name, capitalization: .words, autocorrection: .no)
                    DSTextField(label: "Aufgedruckter Packungspreis (€)", placeholder: "0,00",
                                text: $price, keyboard: .decimalPad)
                }
                .padding(.leading, 43)
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.R.control).fill(isSelected && !item.isDepositBlocked ? DS.C.sur : Color.clear))
    }
}

private struct PriceRow: View {
    let item: PresetProduct
    @Binding var name:  String
    @Binding var price: String

    private var priceInvalid: Bool {
        !price.isEmpty && (parseCents(price) ?? 0) <= 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DSTextField(placeholder: "Produktname", text: $name,
                        capitalization: .sentences, autocorrection: .default)
                .frame(maxWidth: .infinity)
            DSTextField(placeholder: "0,00 €", text: $price,
                        keyboard: .decimalPad, alignment: .right,
                        errorText: priceInvalid ? "Muss größer als 0 sein" : nil)
                .frame(width: 160)
        }
    }
}

private struct VatGroupCard: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSSectionLabel(text: title)
            Text(items.joined(separator: " · "))
                .dsFont(.sub)
                .foregroundColor(DS.C.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.sur))
        .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

private struct ReviewRow: View {
    let item:        PresetProduct
    let displayName: String
    let isConfirmed: Bool
    let onConfirm:   (Bool) -> Void

    private var explanation: String {
        item.vatReview == "printed_price_review"
            ? "Preisgebundene Tabakware: Name, Packungsangabe und aufgedruckter Preis müssen stimmen."
            : "Außer-Haus-Satz geprüft — unsere dokumentierte Rezeptur rechtfertigt den ausgewählten Satz."
    }

    var body: some View {
        Toggle(isOn: Binding(get: { isConfirmed }, set: { onConfirm($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(displayName) · \(item.vatRateInhouse) % / \(item.vatRateTakeaway) %")
                    .dsFont(.subBold)
                    .foregroundColor(DS.C.text)
                Text(explanation)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.brassText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(DS.C.acc)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.brassBg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brassText.opacity(0.35), lineWidth: 1))
    }
}

private struct ResultLine: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .dsFont(.raw(17))
                .foregroundColor(tint)
            Text(text)
                .dsFont(.sub)
                .foregroundColor(DS.C.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Visual-Picker (§6.5: 44pt-Ziele, lokalisierte Labels, nie nur Farbe)
// internal: auch ProduktEditSheet/QuickCreate (SortimentView) nutzen ihn

struct VisualPickerSheet: View {
    let selectedKey: String?
    let onSelect:    (String?) -> Void

    var body: some View {
        DSSheetScaffold(
            title:    "Symbol wählen",
            subtitle: "„Ohne Symbol“ ist eine gleichwertige Auswahl",
            icon:     "square.grid.2x2",
            isDirty:  false
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                pickerCell(key: nil)
                ForEach(ProduktVisualCatalog.orderedKeys, id: \.self) { key in
                    pickerCell(key: key)
                }
            }
        } footer: {
            HStack { Spacer() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func pickerCell(key: String?) -> some View {
        let isSelected = key == selectedKey
        Button {
            onSelect(key)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.R.control)
                        .fill(isSelected ? DS.C.accBg : DS.C.sur2)
                        .frame(width: 52, height: 52)
                    if let key, let visual = ProduktVisualCatalog.visual(for: key) {
                        ProductVisualView(visual: visual, size: 24, tint: isSelected ? DS.C.accT : DS.C.text)
                    } else {
                        Image(systemName: "textformat")
                            .dsFont(.raw(20))
                            .foregroundColor(isSelected ? DS.C.accT : DS.C.text)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .dsFont(.raw(15))
                            .foregroundColor(DS.C.acc)
                            .offset(x: 20, y: -20)
                    }
                }
                Text(ProduktVisualCatalog.label(for: key))
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
                    .lineLimit(1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ProduktVisualCatalog.label(for: key))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Wizard") {
    SortimentWizardView()
        .environmentObject(ProductStore.preview)
}

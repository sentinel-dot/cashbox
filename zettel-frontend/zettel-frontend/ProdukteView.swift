// ProdukteView.swift
// cashbox — Produktverwaltung: Tabellen-Layout + Tab-Modal
// Design v3: keine Farbstreifen, 44pt-Aktionen, zentrale Geld-Formatierung.

import SwiftUI

// MARK: - Root

struct ProdukteView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var showAddSheet        = false
    @State private var editingProduct:     Product?
    @State private var editInitialTab:     ProduktFormSheet.ModalTab = .allgemein
    @State private var togglingProduct:    Product?
    @State private var error:              AppError?
    @State private var showError           = false
    @State private var searchText          = ""
    @State private var selectedCategoryId: Int? = nil

    private var filtered: [Product] {
        let byCategory = selectedCategoryId == nil
            ? productStore.products
            : productStore.products.filter { $0.category?.id == selectedCategoryId }
        guard !searchText.isEmpty else { return byCategory }
        return byCategory.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var activeCount:   Int { productStore.products.filter { $0.isActive }.count }
    private var inactiveCount: Int { productStore.products.filter { !$0.isActive }.count }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .dsBannerTransition()
                }

                ProdukteToolbar(
                    searchText:         $searchText,
                    categories:         productStore.categories,
                    selectedCategoryId: $selectedCategoryId,
                    onAdd:              { showAddSheet = true }
                )

                ProdukteStatsBar(
                    total:    productStore.products.count,
                    active:   activeCount,
                    inactive: inactiveCount
                )

                if productStore.isLoading && productStore.products.isEmpty {
                    // Skeleton als Tabellenzeilen statt zentriertem Spinner
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(0..<8, id: \.self) { _ in
                                DSSkeleton(height: 56, cornerRadius: DS.R.control)
                            }
                        }
                        .padding(DS.S.pagePad)
                    }
                } else if filtered.isEmpty {
                    DSEmptyState(
                        icon: searchText.isEmpty ? "tag.slash" : "magnifyingglass",
                        title: searchText.isEmpty ? "Noch keine Produkte" : "Keine Produkte gefunden",
                        message: searchText.isEmpty
                            ? "Tippe auf „Produkt hinzufügen“, um das erste Produkt anzulegen."
                            : "Andere Suchbegriffe probieren.",
                        actionLabel: searchText.isEmpty ? "Produkt hinzufügen" : nil,
                        action: searchText.isEmpty ? { showAddSheet = true } : nil
                    )
                } else {
                    ProdukteTable(
                        products: filtered,
                        onEdit:  { product in
                            editInitialTab = .allgemein
                            editingProduct = product
                        },
                        onPrice: { product in
                            editInitialTab = .preis
                            editingProduct = product
                        },
                        onToggle: { togglingProduct = $0 }
                    )
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .task { await productStore.loadProducts() }
        // Neues Produkt anlegen
        .sheet(isPresented: $showAddSheet) {
            ProduktFormSheet(
                product:        nil,
                categories:     productStore.categories,
                initialTab:     .allgemein,
                onSave:         { data in
                    Task {
                        do {
                            try await productStore.createProduct(
                                name:            data.name,
                                priceCents:      data.priceCents,
                                vatRateInhouse:  data.vatRateInhouse,
                                vatRateTakeaway: data.vatRateTakeaway,
                                categoryId:      data.categoryId
                            )
                            showAddSheet = false
                        } catch let e as AppError { error = e; showError = true }
                        catch { self.error = .unknown(error.localizedDescription); showError = true }
                    }
                },
                onChangePrice:  nil,
                onDeactivate:   nil
            )
        }
        // Produkt bearbeiten
        .sheet(item: $editingProduct) { product in
            ProduktFormSheet(
                product:    product,
                categories: productStore.categories,
                initialTab: editInitialTab,
                onSave:     { data in
                    Task {
                        do {
                            try await productStore.updateProduct(
                                id:             product.id,
                                name:           data.name,
                                vatRateInhouse: data.vatRateInhouse,
                                isActive:       data.isActive,
                                categoryId:     data.categoryId
                            )
                            editingProduct = nil
                        } catch let e as AppError { error = e; showError = true }
                        catch { self.error = .unknown(error.localizedDescription); showError = true }
                    }
                },
                onChangePrice: { newPrice, reason in
                    Task {
                        do {
                            try await productStore.changePrice(
                                productId:     product.id,
                                newPriceCents: newPrice,
                                reason:        reason
                            )
                            editingProduct = nil
                        } catch let e as AppError { error = e; showError = true }
                        catch { self.error = .unknown(error.localizedDescription); showError = true }
                    }
                },
                onDeactivate: {
                    togglingProduct = product
                    editingProduct  = nil
                }
            )
        }
        // Aktiv/Inaktiv bestätigen
        .confirmationDialog(
            togglingProduct?.isActive == true ? "Produkt deaktivieren?" : "Produkt aktivieren?",
            isPresented: Binding(
                get: { togglingProduct != nil },
                set: { if !$0 { togglingProduct = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Abbrechen", role: .cancel) { togglingProduct = nil }
            Button(
                togglingProduct?.isActive == true ? "Deaktivieren" : "Aktivieren",
                role: togglingProduct?.isActive == true ? .destructive : .none
            ) {
                guard let p = togglingProduct else { return }
                togglingProduct = nil
                Task {
                    do {
                        try await productStore.updateProduct(
                            id:             p.id,
                            name:           p.name,
                            vatRateInhouse: p.vatRateInhouse,
                            isActive:       !p.isActive,
                            categoryId:     p.category?.id
                        )
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        } message: {
            if let p = togglingProduct {
                Text(p.isActive
                     ? "\"\(p.name)\" wird nicht mehr im Kassenbetrieb angezeigt."
                     : "\"\(p.name)\" wird wieder im Kassenbetrieb angezeigt.")
            }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }
}

// MARK: - Toolbar

private struct ProdukteToolbar: View {
    @Binding var searchText:         String
    let categories:                  [ProductCategoryRef]
    @Binding var selectedCategoryId: Int?
    let onAdd:                       () -> Void

    @State private var searchFocused = false

    var body: some View {
        HStack(spacing: 12) {
            // Suchfeld
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .dsFont(.raw(14))
                    .foregroundColor(DS.C.text2)
                NoAssistantTextField(
                    placeholder: "Produkt suchen …",
                    text:        $searchText,
                    uiFont:      UIFont.systemFont(ofSize: 15),
                    uiTextColor: UIColor(DS.C.text),
                    isFocused:   $searchFocused
                )
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dsFont(.raw(15))
                            .foregroundColor(DS.C.text2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(searchFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: searchFocused ? 1.5 : 1)
            )
            .animation(DS.M.fast, value: searchFocused)

            // Kategorie-Filter-Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ToolbarFilterPill(label: "Alle", color: nil, isActive: selectedCategoryId == nil) {
                        selectedCategoryId = nil
                    }
                    ForEach(categories) { cat in
                        ToolbarFilterPill(label: cat.name, color: cat.color, isActive: selectedCategoryId == cat.id) {
                            selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id
                        }
                    }
                }
            }

            Spacer()

            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .dsFont(.raw(14, weight: .bold))
                    Text("Produkt hinzufügen")
                }
            }
            .buttonStyle(DSPrimaryButton(height: 42, fullWidth: false))
        }
        .padding(.horizontal, DS.S.pagePad)
        .frame(height: DS.S.topbarHeight + 8)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

private struct ToolbarFilterPill: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let hex = color { Circle().fill(Color(hex: hex)).frame(width: 8, height: 8) }
                Text(label)
                    .dsFont(.raw(14, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(isActive ? DS.C.acc : DS.C.sur2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isActive)
    }
}

// MARK: - Stats Bar

private struct ProdukteStatsBar: View {
    let total:    Int
    let active:   Int
    let inactive: Int

    var body: some View {
        HStack(spacing: 0) {
            StatCell(label: "Produkte gesamt", value: "\(total)", isAccent: true)
            Divider().frame(height: 36)
            StatCell(label: "Aktiv",   value: "\(active)",   isAccent: false)
            Divider().frame(height: 36)
            StatCell(label: "Inaktiv", value: "\(inactive)", isAccent: false)
            Spacer()
        }
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

private struct StatCell: View {
    let label:    String
    let value:    String
    let isAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DSSectionLabel(text: label)
            Text(value)
                .dsFont(.raw(19, weight: .bold), monoDigits: true)
                .foregroundColor(isAccent ? DS.C.accT : DS.C.text)
        }
        .padding(.horizontal, DS.S.pagePad)
        .padding(.vertical, 10)
    }
}

// MARK: - Tabelle

private struct ProdukteTable: View {
    let products:  [Product]
    let onEdit:    (Product) -> Void
    let onPrice:   (Product) -> Void
    let onToggle:  (Product) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProdukteTableHeader()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(products) { product in
                        ProdukteTableRow(
                            product:  product,
                            onEdit:   { onEdit(product) },
                            onPrice:  { onPrice(product) },
                            onToggle: { onToggle(product) }
                        )
                        Rectangle()
                            .fill(DS.C.brdAdaptive)
                            .frame(height: 1)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

private struct ProdukteTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Produkt")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.S.pagePad)
            Text("Kategorie")
                .frame(width: 160, alignment: .leading)
            Text("Preis")
                .frame(width: 110, alignment: .trailing)
            Text("MwSt")
                .frame(width: 90, alignment: .center)
            Text("Status")
                .frame(width: 116, alignment: .center)
            Text("")
                .frame(width: 140)
        }
        .dsFont(.label)
        .textCase(.uppercase)
        .kerning(0.7)
        .foregroundColor(DS.C.text2)
        .frame(height: 40)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

private struct ProdukteTableRow: View {
    let product:  Product
    let onEdit:   () -> Void
    let onPrice:  () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Produktname
            Text(product.name)
                .dsFont(.raw(16, weight: .semibold))
                .foregroundColor(product.isActive ? DS.C.text : DS.C.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.S.pagePad)

            // Kategorie
            HStack(spacing: 6) {
                if let hex = product.category?.color {
                    Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                }
                Text(product.category?.name ?? "—")
                    .dsFont(.sub)
                    .foregroundColor(DS.C.text2)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)

            // Preis
            Text(euroString(product.priceCents))
                .dsFont(.money(16, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(width: 110, alignment: .trailing)

            // MwSt
            Text("\(product.vatRateInhouse) %")
                .dsFont(.mono(13, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(DS.C.sur2))
                .frame(width: 90, alignment: .center)

            // Status
            Group {
                if product.isActive {
                    DSPill(label: "Aktiv", fg: DS.C.accT, bg: DS.C.accBg)
                } else {
                    DSPill(label: "Inaktiv", fg: DS.C.text2, bg: DS.C.sur2)
                }
            }
            .frame(width: 116, alignment: .center)

            // Aktionen
            HStack(spacing: 4) {
                RowActionButton(icon: "pencil",   title: "Bearbeiten",   isDanger: false, action: onEdit)
                RowActionButton(icon: "eurosign", title: "Preis ändern", isDanger: false, action: onPrice)
                RowActionButton(icon: product.isActive ? "xmark" : "checkmark",
                                title: product.isActive ? "Deaktivieren" : "Aktivieren",
                                isDanger: product.isActive,
                                action: onToggle)
            }
            .frame(width: 140, alignment: .center)
        }
        .frame(height: 60)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .contextMenu {
            Button { onEdit()  } label: { Label("Bearbeiten",   systemImage: "pencil") }
            Button { onPrice() } label: { Label("Preis ändern", systemImage: "eurosign") }
            Divider()
            Button(role: product.isActive ? .destructive : .none) { onToggle() } label: {
                Label(product.isActive ? "Deaktivieren" : "Aktivieren",
                      systemImage: product.isActive ? "xmark.circle" : "checkmark.circle")
            }
        }
        .opacity(product.isActive ? 1 : 0.55)
    }
}

private struct RowActionButton: View {
    let icon:     String
    let title:    String
    let isDanger: Bool
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .dsFont(.raw(14, weight: .medium))
                .foregroundColor(isDanger ? DS.C.dangerText : DS.C.text2)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.sur2.opacity(0.7)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Produkt-Form Sheet (Neu + Bearbeiten)

fileprivate struct ProduktFormData {
    var name:            String
    var priceCents:      Int
    var vatRateInhouse:  String
    var vatRateTakeaway: String
    var categoryId:      Int?
    var isActive:        Bool
}

fileprivate struct ProduktFormSheet: View {
    let product:       Product?
    let categories:    [ProductCategoryRef]
    let initialTab:    ModalTab
    let onSave:        (ProduktFormData) -> Void
    let onChangePrice: ((Int, String) -> Void)?
    let onDeactivate:  (() -> Void)?

    enum ModalTab: String, CaseIterable {
        case allgemein    = "Allgemein"
        case preis        = "Preis & Steuer"
        case modifikatoren = "Modifikatoren"
    }

    @Environment(\.dismiss) private var dismiss

    @State private var activeTab:      ModalTab = .allgemein

    // Allgemein
    @State private var name            = ""
    @State private var selectedCat:    Int?     = nil
    @State private var isActive        = true

    // Preis & Steuer
    @State private var vatRateInhouse  = "19"
    @State private var vatRateTakeaway = "19"
    @State private var newPriceText    = ""
    @State private var priceReason     = ""

    // Neues Produkt: Preis
    @State private var newProdPriceText = ""

    var isEdit: Bool { product != nil }

    var prodPriceCents: Int {
        parseCents(newProdPriceText)
    }
    var changePriceCents: Int { parseCents(newPriceText) }

    var canSaveMain:  Bool { !name.isEmpty && (!isEdit ? prodPriceCents > 0 : true) }
    var canSavePrice: Bool { changePriceCents > 0 && !priceReason.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            modalHead
            if isEdit { tabBar }
            scrollContent
            modalFooter
        }
        .background(DS.C.sur)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Formular — kein versehentliches Weg-Wischen (X ist der Ausweg)
        .interactiveDismissDisabled(true)
        .onAppear {
            activeTab = initialTab
            if let p = product {
                name           = p.name
                vatRateInhouse = p.vatRateInhouse
                vatRateTakeaway = p.vatRateTakeaway ?? "19"
                selectedCat    = p.category?.id
                isActive       = p.isActive
            }
        }
    }

    // MARK: Head

    private var modalHead: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.C.accBg)
                    .frame(width: 40, height: 40)
                Image(systemName: isEdit ? "pencil" : "plus")
                    .dsFont(.raw(16, weight: .semibold))
                    .foregroundColor(DS.C.accT)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isEdit ? (product?.name ?? "Produkt") : "Neues Produkt")
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
                Text(isEdit
                     ? "Produkt bearbeiten · Erstellt \(formatCreatedAt(product?.createdAt))"
                     : "Produkt anlegen")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .dsFont(.raw(13, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.C.sur2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }

    // MARK: Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ModalTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(DS.M.base) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .dsFont(.raw(15, weight: activeTab == tab ? .semibold : .medium))
                        .foregroundColor(activeTab == tab ? DS.C.accT : DS.C.text2)
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .overlay(
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(activeTab == tab ? DS.C.acc : Color.clear),
                            alignment: .bottom
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(DS.M.fast, value: activeTab)
            }
            Spacer()
        }
        .padding(.leading, 6)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }

    // MARK: Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            if isEdit {
                switch activeTab {
                case .allgemein:     allgemeinTab
                case .preis:         preisTab
                case .modifikatoren: modifikatorenTab
                }
            } else {
                newProductForm
            }
        }
    }

    // MARK: Tab: Allgemein

    private var allgemeinTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            PFField(label: "Produktname", placeholder: "z.B. Shisha Standard", text: $name)

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Kategorie")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CatChip(label: "Keine", color: nil, isActive: selectedCat == nil) { selectedCat = nil }
                            ForEach(categories) { cat in
                                CatChip(label: cat.name, color: cat.color, isActive: selectedCat == cat.id) {
                                    selectedCat = selectedCat == cat.id ? nil : cat.id
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Produkt aktiv")
                        .dsFont(.subBold)
                        .foregroundColor(DS.C.text)
                    Text("Inaktive Produkte erscheinen nicht im Kassenbetrieb")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .tint(DS.C.acc)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
            .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
        }
        .padding(20)
    }

    // MARK: Tab: Preis & Steuer

    private var preisTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // GoBD-Hinweis
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .dsFont(.raw(14))
                    .foregroundColor(DS.C.brassText)
                    .padding(.top, 1)
                Text("Preisänderungen werden als neue Einträge in der Preishistorie gespeichert (GoBD). Bestehende Bons bleiben unverändert.")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.brassText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.brassBg))

            // 2 Spalten: Neuer Preis + MwSt
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    PFField(label: "Neuer Preis (€)", placeholder: "0,00", text: $newPriceText, keyboardType: .decimalPad)
                    Text("Änderung erzeugt neuen Historieneintrag")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "MwSt. Inhaus")
                    DSSegmentedControl(selection: $vatRateInhouse, options: [
                        (value: "7", label: "7 %"),
                        (value: "19", label: "19 %"),
                    ])
                }
                .frame(maxWidth: .infinity)
            }

            PFField(label: "Grund der Preisänderung (GoBD-Pflicht)", placeholder: "z.B. Lieferantenpreiserhöhung", text: $priceReason)

            Button {
                onChangePrice?(changePriceCents, priceReason)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.doc").dsFont(.raw(14))
                    Text("Preis speichern")
                }
            }
            .buttonStyle(DSPrimaryButton(height: 48))
            .disabled(!canSavePrice)

            // Preishistorie
            VStack(alignment: .leading, spacing: 10) {
                DSSectionLabel(text: "Preishistorie")

                if let p = product {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            MoneyText(cents: p.priceCents, size: 16, weight: .bold, color: DS.C.accT)
                            Text("Aktueller Preis")
                                .dsFont(.caption)
                                .foregroundColor(DS.C.text2)
                        }
                        Spacer()
                        DSPill(label: "Aktuell", fg: DS.C.accT, bg: DS.C.accBg, showDot: false)
                    }
                    .padding(.vertical, 12)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
                }
            }
        }
        .padding(20)
    }

    // MARK: Tab: Modifikatoren

    private var modifikatorenTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = product, !p.modifierGroups.isEmpty {
                ForEach(p.modifierGroups) { group in
                    ModifierGroupCard(group: group)
                }
            } else {
                DSEmptyState(
                    icon: "slider.horizontal.3",
                    title: "Keine Modifikatoren",
                    message: "Dieses Produkt hat noch keine Modifier-Gruppen."
                )
                .padding(.top, 30)
            }
        }
        .padding(20)
    }

    // MARK: Neues Produkt Form

    private var newProductForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            PFField(label: "Produktname", placeholder: "z.B. Shisha Standard", text: $name)
            PFField(label: "Preis (€)", placeholder: "0,00", text: $newProdPriceText, keyboardType: .decimalPad)

            VStack(alignment: .leading, spacing: 8) {
                DSSectionLabel(text: "MwSt. Inhaus")
                DSSegmentedControl(selection: $vatRateInhouse, options: [
                    (value: "7", label: "7 %"),
                    (value: "19", label: "19 %"),
                ])
            }

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Kategorie")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CatChip(label: "Keine", color: nil, isActive: selectedCat == nil) { selectedCat = nil }
                            ForEach(categories) { cat in
                                CatChip(label: cat.name, color: cat.color, isActive: selectedCat == cat.id) {
                                    selectedCat = selectedCat == cat.id ? nil : cat.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: Footer

    private var modalFooter: some View {
        HStack(spacing: 10) {
            if isEdit {
                Button {
                    onDeactivate?()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: product?.isActive == true ? "xmark.circle" : "checkmark.circle")
                            .dsFont(.raw(14))
                        Text(product?.isActive == true ? "Deaktivieren" : "Aktivieren")
                    }
                }
                .buttonStyle(DSDestructiveButton(height: 48, fullWidth: false))
            }

            Spacer()

            Button("Abbrechen") { dismiss() }
                .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))

            // Haupt-Speichern (versteckt auf Preis-Tab beim Edit)
            if !isEdit || activeTab != .preis {
                Button {
                    onSave(ProduktFormData(
                        name:            name,
                        priceCents:      prodPriceCents,
                        vatRateInhouse:  vatRateInhouse,
                        vatRateTakeaway: vatRateTakeaway,
                        categoryId:      selectedCat,
                        isActive:        isActive
                    ))
                } label: {
                    Text(isEdit ? "Änderungen speichern" : "Produkt speichern")
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!canSaveMain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
    }

    // MARK: Helpers

    private func parseCents(_ text: String) -> Int {
        let c = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespaces)
        // .rounded() ist Pflicht: 19.99 * 100 = 1998.99… → Int() würde 1998 abschneiden
        return Int(((Double(c) ?? 0) * 100).rounded())
    }

    private func formatCreatedAt(_ iso: String?) -> String {
        guard let iso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let d = date else { return iso }
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        return df.string(from: d)
    }
}

// MARK: - Modifier-Gruppen-Karte (Modifikatoren-Tab)

private struct ModifierGroupCard: View {
    let group: ModifierGroup

    var metaText: String {
        let req = group.isRequired ? "Pflichtauswahl" : "Optional"
        if let max = group.maxSelections {
            return "\(req) · max. \(max)"
        }
        return "\(req) · unbegrenzt"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .dsFont(.subBold)
                        .foregroundColor(DS.C.text)
                    Text(metaText)
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
                DSPill(
                    label: group.isRequired ? "Pflicht" : "Optional",
                    fg: group.isRequired ? DS.C.brassText : DS.C.text2,
                    bg: group.isRequired ? DS.C.brassBg : DS.C.sur2,
                    showDot: false
                )
            }
            .padding(14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)

            // Optionen-Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.options) { opt in
                        HStack(spacing: 5) {
                            Text(opt.name)
                                .dsFont(.caption)
                                .foregroundColor(DS.C.text)
                            if opt.priceDeltaCents != 0 {
                                Text("+ \(euroString(opt.priceDeltaCents))")
                                    .dsFont(.money(12, weight: .medium))
                                    .foregroundColor(DS.C.accT)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DS.C.sur))
                        .overlay(Capsule().strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                    }
                }
                .padding(14)
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
        .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

// MARK: - Shared Sub-Components

// Dünner Alias auf DSTextField (eine Feld-Quelle app-weit)
private struct PFField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        DSTextField(label: label, placeholder: placeholder, text: $text,
                    keyboard: keyboardType,
                    capitalization: .sentences, autocorrection: .default)
    }
}

private struct CatChip: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let hex = color { Circle().fill(Color(hex: hex)).frame(width: 8, height: 8) }
                Text(label)
                    .dsFont(.raw(14, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(isActive ? DS.C.acc : DS.C.sur2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Produktliste") {
    ProdukteView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    ProdukteView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

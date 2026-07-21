// SortimentView.swift
// cashbox — S17A: EIN Betreiber-Bereich für Produkte + Kategorien.
// Kategorienleiste links, Produkte rechts (Kassenansicht = echte ProductCard-Kacheln
// oder Liste), Suche, Aktiv/Inaktiv-Filter, Inline-Kategorieanlage, Reihenfolge-Modus.
// Ersetzt ProdukteView + KategorienView (gelöscht in S17A).

import SwiftUI

// MARK: - Root

struct SortimentView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    enum ViewMode: String { case kacheln, liste }
    enum StatusFilter: String { case alle, aktiv, inaktiv }

    @State private var selectedCategoryId: Int? = nil
    @State private var searchText   = ""
    @State private var viewMode:     ViewMode     = .kacheln
    @State private var statusFilter: StatusFilter = .aktiv

    @State private var showQuickCreate  = false
    @State private var editingProduct:  Product? = nil
    @State private var togglingProduct: Product? = nil
    @State private var editingCategory: ProductCategoryRef? = nil
    @State private var deleteCategoryTarget: ProductCategoryRef? = nil
    @State private var showReorder = false

    @State private var error: AppError?
    @State private var showError = false

    // ── Abgeleitete Daten ──────────────────────────────────────────────────

    private var filtered: [Product] {
        var list = productStore.products
        if let id = selectedCategoryId { list = list.filter { $0.category?.id == id } }
        switch statusFilter {
        case .alle:    break
        case .aktiv:   list = list.filter { $0.isActive }
        case .inaktiv: list = list.filter { !$0.isActive }
        }
        guard !searchText.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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

                SortimentToolbar(
                    searchText:    $searchText,
                    viewMode:      $viewMode,
                    statusFilter:  $statusFilter,
                    activeCount:   activeCount,
                    inactiveCount: inactiveCount,
                    onReorder:     { showReorder = true },
                    onAdd:         { showQuickCreate = true }
                )

                HStack(spacing: 0) {
                    KategorienRail(
                        categories:         productStore.allCategories,
                        products:           productStore.products,
                        selectedCategoryId: $selectedCategoryId,
                        onEdit:             { editingCategory = $0 },
                        onDelete:           { deleteCategoryTarget = $0 },
                        onCreate:           { name, color in
                            Task { await createCategory(name: name, color: color) }
                        }
                    )
                    .frame(width: 300)
                    .overlay(Rectangle().frame(width: 1).foregroundColor(DS.C.brdAdaptive), alignment: .trailing)

                    productArea
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .task {
            await productStore.loadProducts(includeInactive: true)
            await productStore.loadCategories()
        }
        .sheet(isPresented: $showQuickCreate) {
            ProduktQuickCreateSheet(
                categories:        productStore.allCategories,
                preselectedCatId:  selectedCategoryId,
                onSave:            { data in await createProduct(data) }
            )
        }
        .sheet(item: $editingProduct) { product in
            ProduktEditSheet(
                product:    product,
                categories: productStore.allCategories,
                onSave:     { name, catId, isActive in
                    await updateProduct(product, name: name, categoryId: catId, isActive: isActive)
                },
                onChangePrice: { cents in await changePrice(product, cents: cents) }
            )
        }
        .sheet(item: $editingCategory) { cat in
            KategorieEditSheet(
                category: cat,
                onSave:   { name, color in await updateCategory(cat, name: name, color: color) },
                onDelete: {
                    editingCategory = nil
                    deleteCategoryTarget = cat
                }
            )
        }
        .sheet(isPresented: $showReorder) {
            ReihenfolgeSheet(
                categories: productStore.allCategories,
                products:   productStore.products,
                onApply:    { catIds, productOrders in
                    await applyReorder(categoryIds: catIds, productOrders: productOrders)
                }
            )
        }
        // Produkt aktivieren/deaktivieren
        .confirmationDialog(
            togglingProduct?.isActive == true ? "Produkt deaktivieren?" : "Produkt aktivieren?",
            isPresented: Binding(
                get: { togglingProduct != nil },
                set: { if !$0 { togglingProduct = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                togglingProduct?.isActive == true ? "Deaktivieren" : "Aktivieren",
                role: togglingProduct?.isActive == true ? .destructive : .none
            ) {
                guard let p = togglingProduct else { return }
                togglingProduct = nil
                Task { await updateProduct(p, name: nil, categoryId: nil, isActive: !p.isActive) }
            }
            Button("Abbrechen", role: .cancel) { togglingProduct = nil }
        } message: {
            if let p = togglingProduct {
                Text(p.isActive
                     ? "\"\(p.name)\" wird nicht mehr im Kassenbetrieb angezeigt. Du kannst es hier jederzeit wieder aktivieren."
                     : "\"\(p.name)\" wird wieder im Kassenbetrieb angezeigt.")
            }
        }
        // Kategorie löschen — Copy entspricht dem Backend-Verhalten (409 bei aktiven Produkten)
        .confirmationDialog(
            "\"\(deleteCategoryTarget?.name ?? "")\" löschen?",
            isPresented: Binding(
                get: { deleteCategoryTarget != nil },
                set: { if !$0 { deleteCategoryTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let cat = deleteCategoryTarget else { return }
                if selectedCategoryId == cat.id { selectedCategoryId = nil }
                Task { await deleteCategory(cat) }
            }
            Button("Abbrechen", role: .cancel) { deleteCategoryTarget = nil }
        } message: {
            Text("Die Kategorie wird deaktiviert. Kategorien mit aktiven Produkten können nicht gelöscht werden — bitte Produkte zuerst verschieben oder deaktivieren.")
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    // ── Produktbereich (rechts) ────────────────────────────────────────────

    @ViewBuilder
    private var productArea: some View {
        if productStore.isLoading && productStore.products.isEmpty {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(0..<9, id: \.self) { _ in
                        DSSkeleton(height: 108, cornerRadius: 12)
                    }
                }
                .padding(20)
            }
        } else if productStore.products.isEmpty {
            DSEmptyState(
                icon: "tag.slash",
                title: "Noch keine Produkte",
                message: "Lege dein Sortiment an: Kategorien links, Produkte hier.",
                actionLabel: "Erstes Produkt anlegen",
                action: { showQuickCreate = true }
            )
        } else if filtered.isEmpty {
            DSEmptyState(
                icon: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
                title: "Keine Produkte gefunden",
                message: searchText.isEmpty
                    ? "Für diese Kombination aus Kategorie und Filter gibt es keine Produkte."
                    : "Andere Suchbegriffe probieren."
            )
        } else {
            switch viewMode {
            case .kacheln:
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(filtered) { product in
                            ProductCard(product: product, dimmed: !product.isActive) {
                                editingProduct = product
                            }
                            .contextMenu {
                                Button { editingProduct = product } label: { Label("Bearbeiten", systemImage: "pencil") }
                                Divider()
                                Button(role: product.isActive ? .destructive : .none) { togglingProduct = product } label: {
                                    Label(product.isActive ? "Deaktivieren" : "Aktivieren",
                                          systemImage: product.isActive ? "xmark.circle" : "checkmark.circle")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            case .liste:
                SortimentListe(
                    products: filtered,
                    onEdit:   { editingProduct = $0 },
                    onToggle: { togglingProduct = $0 }
                )
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────

    private func createProduct(_ data: ProduktQuickCreateSheet.FormData) async {
        do {
            try await productStore.createProduct(
                name: data.name, priceCents: data.priceCents,
                vatRateInhouse: data.vatRateInhouse, vatRateTakeaway: data.vatRateTakeaway,
                categoryId: data.categoryId
            )
            showQuickCreate = false
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func updateProduct(_ product: Product, name: String?, categoryId: Int?, isActive: Bool?) async {
        do {
            try await productStore.updateProduct(id: product.id, name: name, isActive: isActive, categoryId: categoryId)
            editingProduct = nil
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func changePrice(_ product: Product, cents: Int) async {
        do {
            try await productStore.changePrice(productId: product.id, newPriceCents: cents)
            editingProduct = nil
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func createCategory(name: String, color: String?) async {
        // Ans Ende der Leiste anhängen — nicht hart 999
        let nextSort = (productStore.allCategories.map(\.sortOrder).max() ?? 0) + 10
        do {
            try await productStore.createCategory(name: name, color: color, sortOrder: nextSort)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func updateCategory(_ cat: ProductCategoryRef, name: String, color: String?) async {
        do {
            try await productStore.updateCategory(id: cat.id, name: name, color: color, sortOrder: nil)
            editingCategory = nil
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func deleteCategory(_ cat: ProductCategoryRef) async {
        do {
            try await productStore.deleteCategory(id: cat.id)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
        deleteCategoryTarget = nil
    }

    private func applyReorder(categoryIds: [Int]?, productOrders: [Int?: [Int]]) async {
        do {
            if let ids = categoryIds {
                try await productStore.reorderCategories(orderedIds: ids)
            }
            for (catId, ids) in productOrders {
                try await productStore.reorderProducts(categoryId: catId, orderedIds: ids)
            }
            showReorder = false
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }
}

// MARK: - Toolbar

private struct SortimentToolbar: View {
    @Binding var searchText:   String
    @Binding var viewMode:     SortimentView.ViewMode
    @Binding var statusFilter: SortimentView.StatusFilter
    let activeCount:   Int
    let inactiveCount: Int
    let onReorder:     () -> Void
    let onAdd:         () -> Void

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
            .frame(width: 220)
            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(searchFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: searchFocused ? 1.5 : 1)
            )
            .animation(DS.M.fast, value: searchFocused)

            // Kassenansicht / Liste
            DSSegmentedControl(selection: $viewMode, options: [
                (value: .kacheln, label: "Kassenansicht"),
                (value: .liste,   label: "Liste"),
            ])
            .frame(width: 230)

            // Aktiv / Inaktiv
            DSSegmentedControl(selection: $statusFilter, options: [
                (value: .aktiv,   label: "Aktiv (\(activeCount))"),
                (value: .inaktiv, label: "Inaktiv (\(inactiveCount))"),
                (value: .alle,    label: "Alle"),
            ])
            .frame(width: 280)

            Spacer()

            Button(action: onReorder) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.arrow.down")
                        .dsFont(.raw(14, weight: .semibold))
                    Text("Reihenfolge")
                }
            }
            .buttonStyle(DSSecondaryButton(height: 42, fullWidth: false))

            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .dsFont(.raw(14, weight: .bold))
                    Text("Neues Produkt")
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

// MARK: - Kategorien-Rail (links)

private struct KategorienRail: View {
    let categories: [ProductCategoryRef]
    let products:   [Product]
    @Binding var selectedCategoryId: Int?
    let onEdit:   (ProductCategoryRef) -> Void
    let onDelete: (ProductCategoryRef) -> Void
    let onCreate: (String, String?) -> Void

    @State private var showInlineAdd = false
    @State private var newName  = ""
    @State private var newColor = ""

    private func count(for catId: Int?) -> Int {
        guard let id = catId else { return products.count }
        return products.filter { $0.category?.id == id }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                DSSectionLabel(text: "Kategorien")
                    .padding(.horizontal, 6)
                    .padding(.top, 4)

                RailRow(
                    label: "Alle Produkte", color: nil, count: count(for: nil),
                    isSelected: selectedCategoryId == nil,
                    onTap: { selectedCategoryId = nil }
                )

                ForEach(categories) { cat in
                    RailRow(
                        label: cat.name, color: cat.color, count: count(for: cat.id),
                        isSelected: selectedCategoryId == cat.id,
                        onTap: { selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id }
                    )
                    .contextMenu {
                        Button { onEdit(cat) } label: { Label("Bearbeiten", systemImage: "pencil") }
                        Button(role: .destructive) { onDelete(cat) } label: { Label("Löschen", systemImage: "trash") }
                    }
                }

                // Inline-Kategorieanlage (UX-S2)
                if showInlineAdd {
                    VStack(alignment: .leading, spacing: 10) {
                        DSTextField(placeholder: "Name der Kategorie", text: $newName,
                                    capitalization: .sentences, autocorrection: .default)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                            ForEach(SColorPresets.all, id: \.self) { hex in
                                SColorSwatch(hex: hex, isSelected: newColor == "#\(hex)") {
                                    newColor = newColor == "#\(hex)" ? "" : "#\(hex)"
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Abbrechen") {
                                showInlineAdd = false; newName = ""; newColor = ""
                            }
                            .buttonStyle(DSSecondaryButton(height: 40, fullWidth: false))
                            Button("Anlegen") {
                                onCreate(newName.trimmingCharacters(in: .whitespaces),
                                         newColor.isEmpty ? nil : newColor)
                                showInlineAdd = false; newName = ""; newColor = ""
                            }
                            .buttonStyle(DSPrimaryButton(height: 40, fullWidth: false))
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.sur))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.acc, lineWidth: 1))
                } else {
                    Button {
                        showInlineAdd = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .dsFont(.raw(14, weight: .semibold))
                            Text("Neue Kategorie")
                                .dsFont(.raw(15, weight: .semibold))
                        }
                        .foregroundColor(DS.C.accT)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(DS.C.bg)
    }
}

private struct RailRow: View {
    let label:      String
    let color:      String?
    let count:      Int
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if let hex = color {
                    Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .dsFont(.raw(13, weight: .medium))
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                }
                Text(label)
                    .dsFont(.raw(15, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .dsFont(.caption, monoDigits: true)
                    .foregroundColor(DS.C.text2)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: DS.R.button).fill(isSelected ? DS.C.accBg : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: DS.R.button))
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isSelected)
    }
}

// MARK: - Liste (rechte Ansicht 2)

private struct SortimentListe: View {
    let products: [Product]
    let onEdit:   (Product) -> Void
    let onToggle: (Product) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(products) { product in
                    HStack(spacing: 0) {
                        Text(product.name)
                            .dsFont(.raw(16, weight: .semibold))
                            .foregroundColor(product.isActive ? DS.C.text : DS.C.text2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, DS.S.pagePad)

                        HStack(spacing: 6) {
                            if let hex = product.category?.color {
                                Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                            }
                            Text(product.category?.name ?? "—")
                                .dsFont(.sub)
                                .foregroundColor(DS.C.text2)
                                .lineLimit(1)
                        }
                        .frame(width: 150, alignment: .leading)

                        Text(euroString(product.priceCents))
                            .dsFont(.money(16, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .frame(width: 100, alignment: .trailing)

                        Text("\(product.vatRateInhouse) %")
                            .dsFont(.mono(13, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .frame(width: 70, alignment: .center)

                        Group {
                            if product.isActive {
                                DSPill(label: "Aktiv", fg: DS.C.accT, bg: DS.C.accBg)
                            } else {
                                DSPill(label: "Inaktiv", fg: DS.C.text2, bg: DS.C.sur2)
                            }
                        }
                        .frame(width: 100, alignment: .center)

                        HStack(spacing: 4) {
                            SRowActionButton(icon: "pencil", title: "Bearbeiten") { onEdit(product) }
                            SRowActionButton(
                                icon: product.isActive ? "xmark" : "checkmark",
                                title: product.isActive ? "Deaktivieren" : "Aktivieren",
                                isDanger: product.isActive
                            ) { onToggle(product) }
                        }
                        .frame(width: 100, alignment: .center)
                    }
                    .frame(height: 58)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(product) }
                    .opacity(product.isActive ? 1 : 0.6)

                    Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

private struct SRowActionButton: View {
    let icon:     String
    let title:    String
    var isDanger: Bool = false
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
        .accessibilityLabel(title)
    }
}

// MARK: - Farb-Presets (geteilt)

enum SColorPresets {
    // Datenfarben in der Ledger-Signatur: gedämpfte, erdige Mitteltöne
    static let all = ["4a7310","9a6a0b","b4552d","9e2f42","6e5a9e","3a7ca5","2e8c81","6b7267"]
}

struct SColorSwatch: View {
    let hex:        String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#\(hex)"))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .dsFont(.raw(12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 30, minHeight: 30)
        .accessibilityLabel("Farbe \(hex)\(isSelected ? ", ausgewählt" : "")")
        .scaleEffect(isSelected ? 1.07 : 1.0)
        .animation(DS.M.fast, value: isSelected)
    }
}

// MARK: - Produkt anlegen (Kurz-Flow: Name + Preis + Kategorie)

struct ProduktQuickCreateSheet: View {
    struct FormData {
        let name:            String
        let priceCents:      Int
        let vatRateInhouse:  String
        let vatRateTakeaway: String
        let categoryId:      Int?
    }

    let categories:       [ProductCategoryRef]
    let preselectedCatId: Int?
    let onSave:           (FormData) async -> Void

    @State private var name      = ""
    @State private var priceText = ""
    @State private var selectedCat: Int? = nil
    @State private var showMore  = false
    @State private var vatInhouse  = "19"
    @State private var vatTakeaway = "19"
    @State private var isSaving  = false

    private var priceCents: Int? { parseCents(priceText) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (priceCents ?? 0) > 0
    }
    private var isDirty: Bool { !name.isEmpty || !priceText.isEmpty }

    var body: some View {
        DSSheetScaffold(
            title:    "Neues Produkt",
            subtitle: "Name, Preis und Kategorie genügen",
            icon:     "plus",
            isDirty:  isDirty
        ) {
            VStack(alignment: .leading, spacing: 18) {
                DSTextField(label: "Produktname", placeholder: "z.B. Shisha Klassik", text: $name,
                            capitalization: .sentences, autocorrection: .default)

                DSTextField(label: "Preis (€)", placeholder: "0,00", text: $priceText,
                            keyboard: .decimalPad,
                            errorText: !priceText.isEmpty && (priceCents ?? 0) <= 0 ? "Preis muss größer als 0,00 € sein." : nil)

                if !categories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DSSectionLabel(text: "Kategorie")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                SCatChip(label: "Keine", color: nil, isActive: selectedCat == nil) { selectedCat = nil }
                                ForEach(categories) { cat in
                                    SCatChip(label: cat.name, color: cat.color, isActive: selectedCat == cat.id) {
                                        selectedCat = selectedCat == cat.id ? nil : cat.id
                                    }
                                }
                            }
                        }
                    }
                }

                // Steuer progressiv — Default 19/19 ist für die meisten Produkte richtig
                DisclosureGroup(isExpanded: $showMore) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            DSSectionLabel(text: "MwSt. Inhaus")
                            DSSegmentedControl(selection: $vatInhouse, options: [
                                (value: "7", label: "7 %"),
                                (value: "19", label: "19 %"),
                            ])
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            DSSectionLabel(text: "MwSt. Außer Haus")
                            DSSegmentedControl(selection: $vatTakeaway, options: [
                                (value: "7", label: "7 %"),
                                (value: "19", label: "19 %"),
                            ])
                        }
                        Text("Modifikatoren (z.B. Geschmacksrichtungen) kannst du nach dem Anlegen im Produkt ergänzen.")
                            .dsFont(.caption)
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Weitere Einstellungen")
                        .dsFont(.subBold)
                        .foregroundColor(DS.C.text)
                }
                .tint(DS.C.text2)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                Button {
                    guard let cents = priceCents, !isSaving else { return }
                    isSaving = true
                    Task {
                        await onSave(FormData(
                            name: name.trimmingCharacters(in: .whitespaces),
                            priceCents: cents,
                            vatRateInhouse: vatInhouse,
                            vatRateTakeaway: vatTakeaway,
                            categoryId: selectedCat
                        ))
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Produkt speichern")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!canSave || isSaving)
            }
        }
        .presentationDetents([.large])
        .onAppear { selectedCat = preselectedCatId }
    }
}

struct SCatChip: View {
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

// MARK: - Produkt bearbeiten

private struct ProduktEditSheet: View {
    let product:       Product
    let categories:    [ProductCategoryRef]
    let onSave:        (String?, Int?, Bool?) async -> Void
    let onChangePrice: (Int) async -> Void

    @State private var name        = ""
    @State private var selectedCat: Int? = nil
    @State private var isActive    = true
    @State private var newPriceText = ""
    @State private var isSaving    = false

    private var newPriceCents: Int? { parseCents(newPriceText) }
    private var isDirty: Bool {
        name != product.name || selectedCat != product.category?.id
            || isActive != product.isActive || !newPriceText.isEmpty
    }

    var body: some View {
        DSSheetScaffold(
            title:    product.name,
            subtitle: "Produkt bearbeiten",
            icon:     "pencil",
            isDirty:  isDirty
        ) {
            VStack(alignment: .leading, spacing: 18) {
                DSTextField(label: "Produktname", placeholder: "Name", text: $name,
                            capitalization: .sentences, autocorrection: .default)

                if !categories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DSSectionLabel(text: "Kategorie")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                SCatChip(label: "Keine", color: nil, isActive: selectedCat == nil) { selectedCat = nil }
                                ForEach(categories) { cat in
                                    SCatChip(label: cat.name, color: cat.color, isActive: selectedCat == cat.id) {
                                        selectedCat = selectedCat == cat.id ? nil : cat.id
                                    }
                                }
                            }
                        }
                    }
                }

                // Aktiv-Toggle
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

                // ── Preis (GoBD: eigener Pfad) ────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DSSectionLabel(text: "Preis")
                        Spacer()
                        MoneyText(cents: product.priceCents, size: 16, weight: .bold, color: DS.C.accT)
                    }

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

                    HStack(spacing: 10) {
                        DSTextField(placeholder: "Neuer Preis, z.B. 4,50", text: $newPriceText,
                                    keyboard: .decimalPad)
                        Button {
                            guard let cents = newPriceCents, cents > 0, !isSaving else { return }
                            isSaving = true
                            Task { await onChangePrice(cents); isSaving = false }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.doc").dsFont(.raw(14))
                                Text("Preis speichern")
                            }
                        }
                        .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                        .disabled((newPriceCents ?? 0) <= 0 || isSaving)
                    }
                }

                // Modifikatoren (read-only Übersicht)
                if !product.modifierGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DSSectionLabel(text: "Modifikatoren")
                        ForEach(product.modifierGroups) { group in
                            HStack {
                                Text(group.name)
                                    .dsFont(.sub)
                                    .foregroundColor(DS.C.text)
                                Spacer()
                                DSPill(
                                    label: group.isRequired ? "Pflicht" : "Optional",
                                    fg: group.isRequired ? DS.C.brassText : DS.C.text2,
                                    bg: group.isRequired ? DS.C.brassBg : DS.C.sur2
                                )
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                            .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                        }
                    }
                }
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        await onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            selectedCat,
                            isActive
                        )
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Änderungen speichern")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            name        = product.name
            selectedCat = product.category?.id
            isActive    = product.isActive
        }
    }
}

// MARK: - Kategorie bearbeiten

private struct KategorieEditSheet: View {
    let category: ProductCategoryRef
    let onSave:   (String, String?) async -> Void
    let onDelete: () -> Void

    @State private var name     = ""
    @State private var colorHex = ""
    @State private var isSaving = false

    private var isDirty: Bool {
        name != category.name || colorHex != (category.color ?? "")
    }

    var body: some View {
        DSSheetScaffold(
            title:    category.name,
            subtitle: "Kategorie bearbeiten",
            icon:     "folder",
            isDirty:  isDirty
        ) {
            VStack(alignment: .leading, spacing: 18) {
                DSTextField(label: "Name", placeholder: "z.B. Heißgetränke", text: $name,
                            capitalization: .sentences, autocorrection: .default)

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Farbe")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(SColorPresets.all, id: \.self) { hex in
                            SColorSwatch(hex: hex, isSelected: colorHex.lowercased() == "#\(hex)") {
                                colorHex = "#\(hex)"
                            }
                        }
                    }
                }
            }
        } footer: {
            HStack(spacing: 10) {
                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash").dsFont(.raw(14))
                        Text("Löschen")
                    }
                }
                .buttonStyle(DSDestructiveButton(height: 48, fullWidth: false))

                Spacer()

                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        await onSave(
                            name.trimmingCharacters(in: .whitespaces),
                            colorHex.isEmpty ? nil : colorHex
                        )
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Speichern")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            name     = category.name
            colorHex = category.color ?? ""
        }
    }
}

// MARK: - Reihenfolge-Modus (native List + .onMove — VoiceOver-Rearrange inklusive)

private struct ReihenfolgeSheet: View {
    let categories: [ProductCategoryRef]
    let products:   [Product]
    /// (geänderte Kategorie-Reihenfolge oder nil, geänderte Produkt-Reihenfolgen je Kategorie)
    let onApply: ([Int]?, [Int?: [Int]]) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var localCats: [ProductCategoryRef] = []
    @State private var catsChanged = false
    @State private var currentCatId: Int? = nil
    @State private var localProds: [Product] = []
    @State private var changedProductOrders: [Int?: [Int]] = [:]
    @State private var isSaving = false

    private var isDirty: Bool { catsChanged || !changedProductOrders.isEmpty }

    var body: some View {
        DSSheetScaffold(
            title:    "Reihenfolge bearbeiten",
            subtitle: "Ziehen zum Sortieren — so erscheint es an der Kasse",
            icon:     "arrow.up.arrow.down",
            isDirty:  isDirty,
            scrolls:  false
        ) {
            HStack(spacing: 0) {
                // Kategorien
                VStack(alignment: .leading, spacing: 0) {
                    DSSectionLabel(text: "Kategorien")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    List {
                        ForEach(localCats) { cat in
                            HStack(spacing: 10) {
                                if let hex = cat.color {
                                    Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                                }
                                Text(cat.name)
                                    .dsFont(.raw(15, weight: currentCatId == cat.id ? .semibold : .medium))
                                    .foregroundColor(currentCatId == cat.id ? DS.C.accT : DS.C.text)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectCategory(cat.id) }
                            .listRowBackground(currentCatId == cat.id ? DS.C.accBg : DS.C.sur)
                        }
                        .onMove { from, to in
                            localCats.move(fromOffsets: from, toOffset: to)
                            catsChanged = true
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }
                .frame(width: 300)
                .overlay(Rectangle().frame(width: 1).foregroundColor(DS.C.brdAdaptive), alignment: .trailing)

                // Produkte der gewählten Kategorie
                VStack(alignment: .leading, spacing: 0) {
                    DSSectionLabel(text: "Produkte · \(currentCatName)")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    if localProds.isEmpty {
                        DSEmptyState(
                            icon: "tag.slash",
                            title: "Keine Produkte",
                            message: "Diese Kategorie enthält keine Produkte."
                        )
                    } else {
                        List {
                            ForEach(localProds) { p in
                                HStack {
                                    Text(p.name)
                                        .dsFont(.raw(15, weight: .medium))
                                        .foregroundColor(p.isActive ? DS.C.text : DS.C.text2)
                                    if !p.isActive {
                                        DSPill(label: "Inaktiv", fg: DS.C.text2, bg: DS.C.sur2)
                                    }
                                    Spacer()
                                    Text(euroString(p.priceCents))
                                        .dsFont(.money(14, weight: .semibold))
                                        .foregroundColor(DS.C.text2)
                                }
                                .listRowBackground(DS.C.sur)
                            }
                            .onMove { from, to in
                                localProds.move(fromOffsets: from, toOffset: to)
                                changedProductOrders[currentCatId] = localProds.map(\.id)
                            }
                        }
                        .listStyle(.plain)
                        .environment(\.editMode, .constant(.active))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))
                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        await onApply(
                            catsChanged ? localCats.map(\.id) : nil,
                            changedProductOrders
                        )
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text("Fertig")
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!isDirty || isSaving)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            localCats = categories
            selectCategory(categories.first?.id)
        }
    }

    private var currentCatName: String {
        localCats.first { $0.id == currentCatId }?.name ?? "Ohne Kategorie"
    }

    private func selectCategory(_ id: Int?) {
        currentCatId = id
        if let pending = changedProductOrders[id] {
            // Bereits umsortiert — lokale Reihenfolge wiederherstellen
            let byId = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            localProds = pending.compactMap { byId[$0] }
        } else {
            localProds = products.filter { $0.category?.id == id }
        }
    }
}

// MARK: - Previews

#Preview("Sortiment") {
    SortimentView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Leer") {
    SortimentView()
        .environmentObject(ProductStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    SortimentView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

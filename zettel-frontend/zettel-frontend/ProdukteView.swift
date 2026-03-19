// ProdukteView.swift
// cashbox — Produktverwaltung: Tabellen-Layout + Tab-Modal nach Referenz-Design

import SwiftUI

// MARK: - Root

struct ProdukteView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

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
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if filtered.isEmpty {
                    EmptyProdukte(hasSearch: !searchText.isEmpty)
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
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
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
        .alert(
            togglingProduct?.isActive == true ? "Produkt deaktivieren?" : "Produkt aktivieren?",
            isPresented: Binding(
                get: { togglingProduct != nil },
                set: { if !$0 { togglingProduct = nil } }
            )
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchFocused = false

    var body: some View {
        HStack(spacing: 10) {
            // Suchfeld
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(DS.C.text2)
                NoAssistantTextField(
                    placeholder: "Produkt suchen …",
                    text:        $searchText,
                    uiFont:      UIFont.systemFont(ofSize: 13),
                    uiTextColor: UIColor(DS.C.text),
                    isFocused:   $searchFocused
                )
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DS.C.text2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(width: 200)
            .background(DS.C.bg)
            .cornerRadius(DS.R.button)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .strokeBorder(searchFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: searchFocused)

            // Kategorie-Filter-Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Produkt hinzufügen")
                        .font(.jakarta(DS.T.loginFooter + 1, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
            }
            .background(DS.C.acc)
            .cornerRadius(DS.R.button)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct ToolbarFilterPill: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let hex = color { Circle().fill(Color(hex: hex)).frame(width: 6, height: 6) }
                Text(label)
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? DS.C.acc : Color.clear)
            .cornerRadius(DS.R.badge)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.badge)
                    .strokeBorder(isActive ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
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
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct StatCell: View {
    let label:    String
    let value:    String
    let isAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold))
                .kerning(0.5)
                .foregroundColor(DS.C.text2)
            Text(value)
                .font(.jakarta(17, weight: .semibold))
                .foregroundColor(isAccent ? DS.C.acc : DS.C.text)
        }
        .padding(.horizontal, 20)
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
                            .fill(DS.C.brdLight)
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
            Text("PRODUKT")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
            Text("KATEGORIE")
                .frame(width: 150, alignment: .leading)
            Text("PREIS")
                .frame(width: 110, alignment: .trailing)
            Text("MWST")
                .frame(width: 86, alignment: .center)
            Text("STATUS")
                .frame(width: 116, alignment: .center)
            Text("")
                .frame(width: 96)
        }
        .font(.jakarta(9, weight: .semibold))
        .kerning(0.5)
        .foregroundColor(DS.C.text2)
        .frame(height: 38)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct ProdukteTableRow: View {
    let product:  Product
    let onEdit:   () -> Void
    let onPrice:  () -> Void
    let onToggle: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Kategorie-Farbstreifen
            Rectangle()
                .fill(product.category.flatMap { Color(hex: $0.color ?? "") } ?? Color.clear)
                .frame(width: 3)

            // Produktname
            Text(product.name)
                .font(.jakarta(14, weight: .semibold))
                .foregroundColor(product.isActive ? DS.C.text : DS.C.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            // Kategorie
            HStack(spacing: 5) {
                if let hex = product.category?.color {
                    Circle().fill(Color(hex: hex)).frame(width: 7, height: 7)
                }
                Text(product.category?.name ?? "—")
                    .font(.jakarta(12, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            // Preis
            Text(formatCents(product.priceCents))
                .font(.jakarta(14, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(width: 110, alignment: .trailing)

            // MwSt-Badge
            MwStBadge(rate: product.vatRateInhouse)
                .frame(width: 86, alignment: .center)

            // Status-Badge
            StatusBadge(isActive: product.isActive)
                .frame(width: 116, alignment: .center)

            // Action-Buttons
            HStack(spacing: 6) {
                RowActionButton(icon: "pencil",        title: "Bearbeiten",    isDanger: false,               action: onEdit)
                RowActionButton(icon: "eurosign",      title: "Preis ändern",  isDanger: false,               action: onPrice)
                RowActionButton(icon: product.isActive ? "xmark" : "checkmark",
                                title: product.isActive ? "Deaktivieren" : "Aktivieren",
                                isDanger: product.isActive,
                                action: onToggle)
            }
            .frame(width: 96, alignment: .center)
        }
        .frame(height: 60)
        .background(isHovered ? DS.C.bg : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
        .opacity(product.isActive ? 1 : 0.6)
    }
}

private struct MwStBadge: View {
    let rate: String
    var is7: Bool { rate == "7" }
    var body: some View {
        Text("\(rate) %")
            .font(.jakarta(10, weight: .semibold))
            .foregroundColor(is7 ? DS.C.freeText : DS.C.warnText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(is7 ? DS.C.freeBg : DS.C.warnBg)
            .cornerRadius(6)
    }
}

private struct StatusBadge: View {
    let isActive: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? DS.C.freeText : DS.C.text2)
                .frame(width: 5, height: 5)
            Text(isActive ? "Aktiv" : "Inaktiv")
                .font(.jakarta(10, weight: .semibold))
                .foregroundColor(isActive ? DS.C.freeText : DS.C.text2)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(isActive ? DS.C.freeBg : DS.C.sur2)
        .cornerRadius(20)
    }
}

private struct RowActionButton: View {
    let icon:     String
    let title:    String
    let isDanger: Bool
    let action:   () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered
                                 ? (isDanger ? DS.C.dangerText : DS.C.text)
                                 : DS.C.text2)
                .frame(width: 28, height: 28)
                .background(isHovered ? (isDanger ? DS.C.dangerBg : DS.C.sur2) : Color.clear)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isHovered
                                      ? (isDanger ? DS.C.dangerText.opacity(0.4) : DS.C.brd(colorScheme))
                                      : DS.C.brd(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .help(title)
    }
}

// MARK: - Leer-Zustand

private struct EmptyProdukte: View {
    let hasSearch: Bool
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : "tag.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DS.C.text2)
            Text(hasSearch ? "Keine Produkte gefunden" : "Noch keine Produkte")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text(hasSearch ? "Andere Suchbegriffe probieren." : "Tippe auf \"Produkt hinzufügen\" um das erste Produkt anzulegen.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @Environment(\.colorScheme) private var colorScheme

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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.C.accBg)
                    .frame(width: 36, height: 36)
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.C.accT)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isEdit ? (product?.name ?? "Produkt") : "Neues Produkt")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text(isEdit
                     ? "Produkt bearbeiten · Erstellt \(formatCreatedAt(product?.createdAt))"
                     : "Produkt anlegen")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }

    // MARK: Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ModalTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.jakarta(12, weight: activeTab == tab ? .semibold : .medium))
                        .foregroundColor(activeTab == tab ? DS.C.accT : DS.C.text2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(activeTab == tab ? DS.C.acc : Color.clear),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: activeTab)
            }
            Spacer()
        }
        .padding(.leading, 6)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
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
        VStack(alignment: .leading, spacing: 16) {
            PFField(label: "Produktname", placeholder: "z.B. Shisha Standard", text: $name)

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KATEGORIE")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
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

            // Active toggle — styled wie Referenz
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Produkt aktiv")
                        .font(.jakarta(12, weight: .medium))
                        .foregroundColor(DS.C.text)
                    Text("Inaktive Produkte erscheinen nicht im Kassensystem")
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .tint(DS.C.freeText)
            }
            .padding(14)
            .background(DS.C.bg)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
        }
        .padding(20)
    }

    // MARK: Tab: Preis & Steuer

    private var preisTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // GoBD-Hinweis
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(DS.C.warnText)
                    .padding(.top, 1)
                Text("Preisänderungen werden als neue Einträge in der Preishistorie gespeichert (GoBD). Bestehende Bons bleiben unverändert.")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.warnText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(DS.C.warnBg)
            .cornerRadius(8)

            // 2 Spalten: Neuer Preis + MwSt
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    PFField(label: "Neuer Preis (€)", placeholder: "0,00", text: $newPriceText, keyboardType: .decimalPad)
                    Text("Änderung erzeugt neuen Historieneintrag")
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MWST. INHAUS")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    HStack(spacing: 6) {
                        ForEach(["7", "19"], id: \.self) { rate in
                            Button {
                                withAnimation(.easeInOut(duration: 0.1)) { vatRateInhouse = rate }
                            } label: {
                                Text("\(rate) %")
                                    .font(.jakarta(12, weight: .semibold))
                                    .foregroundColor(vatRateInhouse == rate ? .white : DS.C.text2)
                                    .padding(.horizontal, 16)
                                    .frame(height: 36)
                                    .background(vatRateInhouse == rate ? DS.C.acc : DS.C.sur2)
                                    .cornerRadius(DS.R.button)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            PFField(label: "Grund der Preisänderung (GoBD-Pflicht)", placeholder: "z.B. Lieferantenpreiserhöhung", text: $priceReason)

            // Preis speichern
            Button {
                onChangePrice?(changePriceCents, priceReason)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "lock.doc").font(.system(size: 12))
                    Text("Preis speichern")
                        .font(.jakarta(12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .background(canSavePrice ? DS.C.acc : DS.C.acc.opacity(0.35))
            .cornerRadius(DS.R.button)
            .disabled(!canSavePrice)
            .buttonStyle(.plain)

            // Preishistorie
            VStack(alignment: .leading, spacing: 0) {
                Text("PREISHISTORIE")
                    .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                    .foregroundColor(DS.C.text2)
                    .padding(.bottom, 10)

                if let p = product {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatCents(p.priceCents))
                                .font(.jakarta(13, weight: .semibold))
                                .foregroundColor(DS.C.acc)
                            Text("Aktueller Preis")
                                .font(.jakarta(11, weight: .regular))
                                .foregroundColor(DS.C.text2)
                        }
                        Spacer()
                        Text("Aktuell")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.freeText)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.C.freeBg)
                            .cornerRadius(20)
                    }
                    .padding(.vertical, 12)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
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
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(DS.C.text2)
                    Text("Keine Modifikatoren")
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text("Dieses Produkt hat noch keine Modifier-Gruppen.")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
        .padding(20)
    }

    // MARK: Neues Produkt Form

    private var newProductForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFField(label: "Produktname", placeholder: "z.B. Shisha Standard", text: $name)
            PFField(label: "Preis (€)", placeholder: "0,00", text: $newProdPriceText, keyboardType: .decimalPad)

            VStack(alignment: .leading, spacing: 6) {
                Text("MWST. INHAUS")
                    .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                    .foregroundColor(DS.C.text2)
                HStack(spacing: 8) {
                    ForEach(["7", "19"], id: \.self) { rate in
                        Button {
                            withAnimation(.easeInOut(duration: 0.1)) { vatRateInhouse = rate }
                        } label: {
                            Text("\(rate) %")
                                .font(.jakarta(13, weight: .semibold))
                                .foregroundColor(vatRateInhouse == rate ? .white : DS.C.text2)
                                .padding(.horizontal, 20)
                                .frame(height: 34)
                                .background(vatRateInhouse == rate ? DS.C.acc : DS.C.sur2)
                                .cornerRadius(DS.R.button)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KATEGORIE")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
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
        HStack(spacing: 8) {
            if isEdit {
                Button {
                    onDeactivate?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: product?.isActive == true ? "xmark.circle" : "checkmark.circle")
                            .font(.system(size: 12))
                        Text(product?.isActive == true ? "Deaktivieren" : "Aktivieren")
                            .font(.jakarta(12, weight: .semibold))
                    }
                    .foregroundColor(product?.isActive == true ? DS.C.dangerText : DS.C.freeText)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.button)
                            .strokeBorder(product?.isActive == true ? DS.C.dangerText : DS.C.freeText, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button("Abbrechen") { dismiss() }
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                .buttonStyle(.plain)

            // Haupt-Speichern-Button (versteckt wenn wir auf Preis-Tab sind beim Edit)
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
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                }
                .background(canSaveMain ? DS.C.acc : DS.C.acc.opacity(0.35))
                .cornerRadius(DS.R.button)
                .disabled(!canSaveMain)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
    }

    // MARK: Helpers

    private func parseCents(_ text: String) -> Int {
        let c = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int((Double(c) ?? 0) * 100)
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
    @Environment(\.colorScheme) private var colorScheme

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
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text(metaText)
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
                Text(group.isRequired ? "Pflicht" : "Optional")
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(group.isRequired ? DS.C.accT : DS.C.text2)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(group.isRequired ? DS.C.accBg : DS.C.sur2)
                    .cornerRadius(20)
            }
            .padding(14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Optionen-Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.options) { opt in
                        HStack(spacing: 4) {
                            Text(opt.name)
                                .font(.jakarta(11, weight: .medium))
                                .foregroundColor(DS.C.text)
                            if opt.priceDeltaCents != 0 {
                                Text("+\(formatCents(opt.priceDeltaCents))")
                                    .font(.jakarta(10, weight: .medium))
                                    .foregroundColor(DS.C.accT)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(DS.C.sur)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                    }
                }
                .padding(14)
            }
        }
        .background(DS.C.bg)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - Shared Sub-Components

private struct PFField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                .foregroundColor(DS.C.text2)
            NoAssistantTextField(
                placeholder:  placeholder,
                text:         $text,
                keyboardType: keyboardType,
                uiFont:       UIFont.systemFont(ofSize: 13),
                uiTextColor:  UIColor(DS.C.text),
                isFocused:    $isFocused
            )
            .padding(.horizontal, 12)
            .frame(height: 36)
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

private struct CatChip: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let hex = color { Circle().fill(Color(hex: hex)).frame(width: 6, height: 6) }
                Text(label)
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isActive ? DS.C.acc : Color.clear)
            .cornerRadius(DS.R.badge)
            .overlay(RoundedRectangle(cornerRadius: DS.R.badge).strokeBorder(isActive ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
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

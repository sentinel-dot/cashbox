// ProdukteView.swift
// cashbox — Produktverwaltung: Liste, Anlegen, Bearbeiten, Preis ändern, Deaktivieren

import SwiftUI

// MARK: - Root

struct ProdukteView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAddSheet  = false
    @State private var editingProduct: Product?
    @State private var pricingProduct: Product?
    @State private var error:        AppError?
    @State private var showError     = false
    @State private var searchText    = ""
    @State private var selectedCategoryId: Int? = nil

    private var filtered: [Product] {
        let byCategory = selectedCategoryId == nil
            ? productStore.products
            : productStore.products.filter { $0.category?.id == selectedCategoryId }
        guard !searchText.isEmpty else { return byCategory }
        return byCategory.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ProdukteTopBar(searchText: $searchText, onAdd: { showAddSheet = true })

                // Kategorie-Filter
                if !productStore.categories.isEmpty {
                    ProdukteFilterBar(
                        categories:         productStore.categories,
                        selectedCategoryId: $selectedCategoryId
                    )
                }

                if productStore.isLoading && productStore.products.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if filtered.isEmpty {
                    EmptyProdukte(hasSearch: !searchText.isEmpty)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                            spacing: 10
                        ) {
                            ForEach(filtered) { product in
                                ProdukteCard(
                                    product:  product,
                                    onEdit:   { editingProduct = product },
                                    onPrice:  { pricingProduct = product }
                                )
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .task { await productStore.loadProducts() }
        .sheet(isPresented: $showAddSheet) {
            ProduktFormSheet(product: nil, categories: productStore.categories) { data in
                Task {
                    do {
                        try await productStore.createProduct(
                            name: data.name, priceCents: data.priceCents,
                            vatRateInhouse: data.vatRateInhouse, vatRateTakeaway: data.vatRateTakeaway,
                            categoryId: data.categoryId
                        )
                        showAddSheet = false
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        .sheet(item: $editingProduct) { product in
            ProduktFormSheet(product: product, categories: productStore.categories) { data in
                Task {
                    do {
                        try await productStore.updateProduct(
                            id: product.id,
                            name: data.name,
                            vatRateInhouse: data.vatRateInhouse,
                            isActive: data.isActive,
                            categoryId: data.categoryId
                        )
                        editingProduct = nil
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        .sheet(item: $pricingProduct) { product in
            PreisAendernSheet(product: product) { newPrice, reason in
                Task {
                    do {
                        try await productStore.changePrice(productId: product.id, newPriceCents: newPrice, reason: reason)
                        pricingProduct = nil
                    } catch let e as AppError { error = e; showError = true }
                    catch { self.error = .unknown(error.localizedDescription); showError = true }
                }
            }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }
}

// MARK: - Top Bar

private struct ProdukteTopBar: View {
    @Binding var searchText: String
    let onAdd: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchFocused = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Produkte")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)

            // Suchfeld
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(DS.C.text2)
                NoAssistantTextField(
                    placeholder:  "Suchen…",
                    text:         $searchText,
                    uiFont:       UIFont.systemFont(ofSize: 13),
                    uiTextColor:  UIColor(DS.C.text),
                    isFocused:    $searchFocused
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
            .frame(maxWidth: 240)
            .background(DS.C.sur2)
            .cornerRadius(DS.R.button)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .strokeBorder(searchFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: searchFocused)

            Spacer()

            Button(action: onAdd) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Produkt")
                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
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

// MARK: - Filter Bar

private struct ProdukteFilterBar: View {
    let categories: [ProductCategoryRef]
    @Binding var selectedCategoryId: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", color: nil, isActive: selectedCategoryId == nil) {
                    selectedCategoryId = nil
                }
                ForEach(categories) { cat in
                    FilterPill(label: cat.name, color: cat.color, isActive: selectedCategoryId == cat.id) {
                        selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

private struct FilterPill: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let hex = color {
                    Circle().fill(Color(hex: hex)).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? DS.C.acc : Color.clear)
            .cornerRadius(DS.R.badge)
            .overlay(RoundedRectangle(cornerRadius: DS.R.badge).strokeBorder(isActive ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Produkt-Karte

private struct ProdukteCard: View {
    let product: Product
    let onEdit:  () -> Void
    let onPrice: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kategorie-Streifen
            if let hex = product.category?.color {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: hex)).frame(height: 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(product.isActive ? DS.C.text : DS.C.text2)
                    .lineLimit(2)

                if let cat = product.category {
                    Text(cat.name)
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                HStack {
                    Text(formatCents(product.priceCents))
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                    Spacer()
                    Text("\(product.vatRateInhouse) %")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                // Aktionen
                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(DS.C.sur2)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: onPrice) {
                        Image(systemName: "eurosign")
                            .font(.system(size: 11))
                            .foregroundColor(DS.C.acc)
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(DS.C.accBg)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            if !product.isActive {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash").font(.system(size: 9))
                    Text("Inaktiv")
                        .font(.jakarta(8, weight: .semibold))
                }
                .foregroundColor(DS.C.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(DS.C.sur2)
            }
        }
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: product.isActive ? 1 : 0.5))
        .opacity(product.isActive ? 1 : 0.65)
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
            Text(hasSearch ? "Andere Suchbegriffe probieren." : "Tippe auf \"Produkt\" um das erste Produkt anzulegen.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Produkt-Formular Sheet

private struct ProduktFormData {
    var name:           String
    var priceCents:     Int
    var vatRateInhouse: String
    var vatRateTakeaway: String
    var categoryId:     Int?
    var isActive:       Bool
}

private struct ProduktFormSheet: View {
    let product:    Product?
    let categories: [ProductCategoryRef]
    let onSave:     (ProduktFormData) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name           = ""
    @State private var priceText      = ""
    @State private var vatRateInhouse = "19"
    @State private var vatRateTakeaway = "19"
    @State private var selectedCat:   Int?    = nil
    @State private var isActive       = true


    var isEdit: Bool { product != nil }
    var priceCents: Int {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
        return Int((Double(cleaned) ?? 0) * 100)
    }
    var canSave: Bool { !name.isEmpty && (isEdit || priceCents > 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(isEdit ? "Produkt bearbeiten" : "Neues Produkt")
                        .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .padding(.top, 8)

                    // Name
                    PFField(label: "Name", placeholder: "z.B. Cappuccino", text: $name)

                    // Preis — nur bei Neu (Änderung über Preishistorie)
                    if !isEdit {
                        PFField(label: "Preis (€)", placeholder: "3,50", text: $priceText, keyboardType: .decimalPad)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 11))
                            Text("Preis über \"Preis ändern\" anpassen (GoBD-konform)")
                                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        }
                        .foregroundColor(DS.C.text2)
                    }

                    // MwSt
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MwSt-Satz (Inhouse)")
                            .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                        HStack(spacing: 8) {
                            ForEach(["7", "19"], id: \.self) { rate in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.1)) { vatRateInhouse = rate }
                                } label: {
                                    Text("\(rate) %")
                                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
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

                    // Kategorie
                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kategorie (optional)")
                                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                                .foregroundColor(DS.C.text2)
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

                    // Aktiv-Toggle (nur bei Edit)
                    if isEdit {
                        Toggle("Produkt aktiv", isOn: $isActive)
                            .font(.jakarta(DS.T.loginBody, weight: .regular))
                            .foregroundColor(DS.C.text)
                            .tint(DS.C.acc)
                    }

                    HStack(spacing: 10) {
                        Button("Abbrechen") { dismiss() }
                            .font(.jakarta(DS.T.loginButton, weight: .medium))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.button)
                            .buttonStyle(.plain)

                        Button {
                            onSave(ProduktFormData(
                                name: name, priceCents: priceCents,
                                vatRateInhouse: vatRateInhouse, vatRateTakeaway: vatRateTakeaway,
                                categoryId: selectedCat, isActive: isActive
                            ))
                        } label: {
                            Text("Speichern")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        }
                        .background(canSave ? DS.C.acc : DS.C.acc.opacity(0.4))
                        .cornerRadius(DS.R.button)
                        .disabled(!canSave)
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            if let p = product {
                name            = p.name
                vatRateInhouse  = p.vatRateInhouse
                vatRateTakeaway = p.vatRateTakeaway ?? "19"
                selectedCat     = p.category?.id
                isActive        = p.isActive
            }
        }
    }
}

private struct PFField: View {
    let label:       String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                .foregroundColor(DS.C.text2)
            NoAssistantTextField(
                placeholder:  placeholder,
                text:         $text,
                keyboardType: keyboardType,
                uiFont:       UIFont.systemFont(ofSize: 14),
                uiTextColor:  UIColor(DS.C.text),
                isFocused:    $isFocused
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
                if let hex = color { Circle().fill(Color(hex: hex)).frame(width: 7, height: 7) }
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

// MARK: - Preis-Ändern Sheet (GoBD: erstellt product_price_history-Eintrag)

private struct PreisAendernSheet: View {
    let product:  Product
    let onSave:   (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var priceText     = ""
    @State private var reason        = ""
    @State private var priceFocused  = false
    @State private var reasonFocused = false

    var newPriceCents: Int {
        let c = priceText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
        return Int((Double(c) ?? 0) * 100)
    }
    var canSave: Bool { newPriceCents > 0 && !reason.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(DS.C.text2.opacity(0.3)).frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 16) {
                Text("Preis ändern")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .padding(.top, 8)

                HStack {
                    Text(product.name)
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    Text("Aktuell: \(formatCents(product.priceCents))")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Neuer Preis (€)")
                        .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder:  "0,00",
                        text:         $priceText,
                        keyboardType: .decimalPad,
                        uiFont:       UIFont.systemFont(ofSize: 14),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $priceFocused
                    )
                    .padding(.horizontal, 12)
                    .frame(height: DS.S.inputHeight)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(priceFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Grund (Pflicht für GoBD-Protokoll)")
                        .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder: "z.B. Lieferantenpreiserhöhung",
                        text:        $reason,
                        uiFont:      UIFont.systemFont(ofSize: 14),
                        uiTextColor: UIColor(DS.C.text),
                        isFocused:   $reasonFocused
                    )
                    .padding(.horizontal, 12)
                    .frame(height: DS.S.inputHeight)
                    .background(DS.C.bg)
                        .cornerRadius(DS.R.input)
                        .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(reasonFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.doc")
                        .font(.system(size: 11))
                    Text("Preisänderung wird in der Preishistorie protokolliert (GoBD). Der alte Preis bleibt erhalten.")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                }
                .foregroundColor(DS.C.text2)

                HStack(spacing: 10) {
                    Button("Abbrechen") { dismiss() }
                        .font(.jakarta(DS.T.loginButton, weight: .medium))
                        .foregroundColor(DS.C.text2)
                        .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.button)
                        .buttonStyle(.plain)

                    Button { onSave(newPriceCents, reason) } label: {
                        Text("Preis ändern")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                    }
                    .background(canSave ? DS.C.acc : DS.C.acc.opacity(0.4))
                    .cornerRadius(DS.R.button)
                    .disabled(!canSave)
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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

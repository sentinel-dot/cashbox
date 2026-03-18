// OrderView.swift
// cashbox — Bestellansicht: Produktkatalog (links) + Warenkorb (rechts)
// Wird als fullScreenCover aus TableOverviewView geöffnet.

import SwiftUI

// MARK: - Root

struct OrderView: View {
    let tableId:   Int?
    let tableName: String?

    @EnvironmentObject var orderStore:   OrderStore
    @EnvironmentObject var productStore: ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Aktuelle Order-ID — nil solange noch keine Order erstellt
    @State private var currentOrderId: Int? = nil

    // Produkt für ModifierSheet — sheet(item:) verhindert Timing-Probleme mit nil-State
    @State private var pendingProduct: Product? = nil

    // Error
    @State private var error: AppError?
    @State private var showError = false

    // Storno-Bestätigung
    @State private var showCancelConfirm = false

    // Bezahlung — paymentOrder cacht die Order beim Öffnen, damit selectedOrder=nil nach pay() den Screen nicht leert
    @State private var showPaymentView = false
    @State private var paymentOrder: OrderDetail? = nil

    var body: some View {
        // NavigationStack verhindert den nested-fullScreenCover-Bug (weißer Screen bei erstem Bezahlen).
        // PaymentView wird per navigationDestination gepusht — kein verschachteltes Modal.
        NavigationStack {
            ZStack(alignment: .top) {
                DS.C.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !networkMonitor.isOnline {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    OrderTopBar(
                        tableName: tableName,
                        orderId:   currentOrderId,
                        hasItems:  !(orderStore.selectedOrder?.items.isEmpty ?? true),
                        onClose:   { dismiss() },
                        onCancel:  { showCancelConfirm = true }
                    )

                    HStack(spacing: 0) {
                        // Links: Produktkatalog
                        ProductCatalog(onProductTap: handleProductTap)
                            .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(DS.C.brdLight)
                            .frame(width: 1)

                        // Rechts: Warenkorb
                        CartPanel(
                            tableName:  tableName,
                            orderId:    currentOrderId,
                            onRemove:   removeItem,
                            onBezahlen: { paymentOrder = orderStore.selectedOrder; showPaymentView = true }
                        )
                        .frame(width: 340)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
            .task {
                await productStore.loadProducts()
                await findOrLoadExistingOrder()
            }
            // ModifierSheet — sheet(item:) garantiert dass product nie nil ist wenn Sheet erscheint
            .sheet(item: $pendingProduct) { product in
                ModifierSelectionSheet(product: product) { selectedOptionIds in
                    Task { await addProductWithModifiers(product, optionIds: selectedOptionIds) }
                }
            }
            // Storno-Bestätigung
            .confirmationDialog(
                "Bestellung stornieren?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Stornieren", role: .destructive) {
                    Task { await performCancelOrder() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die gesamte Bestellung wird storniert. Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .alert("Fehler", isPresented: $showError) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Unbekannter Fehler")
            }
            // PaymentView — Navigation Push statt nested fullScreenCover
            .navigationDestination(isPresented: $showPaymentView) {
                if let order = paymentOrder {
                    PaymentView(order: order, tableName: tableName)
                        .environmentObject(orderStore)
                        .environmentObject(networkMonitor)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .onChange(of: showPaymentView) { showing in
                if !showing {
                    paymentOrder = nil
                    // Zahlung abgeschlossen → Order wurde entfernt → zurück zur Tischübersicht
                    if orderStore.selectedOrder == nil && currentOrderId != nil {
                        dismiss()
                    }
                }
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────

    private func findOrLoadExistingOrder() async {
        await orderStore.loadOrders()
        if let existing = orderStore.orders.first(where: { $0.table?.id == tableId }) {
            currentOrderId = existing.id
            do { try await orderStore.loadOrder(existing.id) }
            catch let e as AppError { error = e; showError = true }
            catch { self.error = .unknown(error.localizedDescription); showError = true }
        }
    }

    private func handleProductTap(_ product: Product) {
        if product.hasRequiredModifiers {
            pendingProduct = product  // sheet(item:) öffnet automatisch
        } else {
            Task { await addProductDirect(product) }
        }
    }

    private func addProductDirect(_ product: Product) async {
        do {
            let orderId = try await ensureOrder()
            try await orderStore.addItem(orderId: orderId, productId: product.id)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func addProductWithModifiers(_ product: Product, optionIds: [Int]) async {
        do {
            let orderId = try await ensureOrder()
            try await orderStore.addItem(orderId: orderId, productId: product.id, modifierOptionIds: optionIds)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func removeItem(itemId: Int) async {
        guard let orderId = currentOrderId else { return }
        do { try await orderStore.removeItem(orderId: orderId, itemId: itemId) }
        catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func performCancelOrder() async {
        guard let orderId = currentOrderId else { dismiss(); return }
        do {
            try await orderStore.cancelOrder(orderId, reason: "Manuell storniert")
            currentOrderId = nil
            dismiss()
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    /// Gibt die aktuelle Order-ID zurück — erstellt bei Bedarf eine neue.
    private func ensureOrder() async throws -> Int {
        if let id = currentOrderId { return id }
        let newOrder = try await orderStore.createOrder(tableId: tableId)
        currentOrderId = newOrder.id
        return newOrder.id
    }
}

// MARK: - Top Bar

private struct OrderTopBar: View {
    let tableName: String?
    let orderId:   Int?
    let hasItems:  Bool
    let onClose:   () -> Void
    let onCancel:  () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Schließen
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Zurück")
                        .font(.jakarta(DS.T.loginButton, weight: .medium))
                }
                .foregroundColor(DS.C.acc)
            }
            .buttonStyle(.plain)

            Rectangle().fill(DS.C.brdLight).frame(width: 1, height: 20)

            // Tisch + Order-ID
            VStack(alignment: .leading, spacing: 1) {
                Text(tableName ?? "Schnellkasse")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                if let id = orderId {
                    Text("Bestellung #\(id)")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }

            Spacer()

            // Storno (nur wenn Order + Items vorhanden)
            if orderId != nil && hasItems {
                Button(action: onCancel) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Stornieren")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "c0392b"))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color(hex: "c0392b").opacity(0.1))
                    .cornerRadius(DS.R.button)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Produktkatalog (links)

private struct ProductCatalog: View {
    @EnvironmentObject var productStore: ProductStore
    let onProductTap: (Product) -> Void

    @State private var selectedCategoryId: Int? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var filteredProducts: [Product] {
        productStore.products(for: selectedCategoryId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kategorie-Filterleiste
            if !productStore.categories.isEmpty {
                CategoryFilterBar(
                    categories:         productStore.categories,
                    selectedCategoryId: $selectedCategoryId
                )
            }

            if productStore.isLoading {
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            } else if filteredProducts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(DS.C.text2)
                    Text("Keine Produkte")
                        .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text("Produkte können in den Einstellungen angelegt werden.")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        ForEach(filteredProducts) { product in
                            ProductCard(product: product) { onProductTap(product) }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(DS.C.bg)
    }
}

private struct CategoryFilterBar: View {
    let categories: [ProductCategoryRef]
    @Binding var selectedCategoryId: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryPill(label: "Alle", color: nil, isSelected: selectedCategoryId == nil) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedCategoryId = nil }
                }
                ForEach(categories) { cat in
                    CategoryPill(
                        label: cat.name,
                        color: cat.color,
                        isSelected: selectedCategoryId == cat.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct CategoryPill: View {
    let label:      String
    let color:      String?
    let isSelected: Bool
    let onTap:      () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let hex = color {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.jakarta(DS.T.zonePill, weight: .semibold))
                    .foregroundColor(isSelected ? .white : DS.C.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? DS.C.acc : Color.clear)
            .cornerRadius(DS.R.badge)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.badge)
                    .strokeBorder(
                        isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProductCard: View {
    let product: Product
    let onTap:   () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Kategorie-Farbbalken (optional)
                if let hex = product.category?.color {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: hex))
                        .frame(height: 3)
                }

                Spacer().frame(height: 2)

                Text(product.name)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack {
                    Text(formatCents(product.priceCents))
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                    Spacer()
                    // Modifier-Indikator
                    if product.hasRequiredModifiers {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                    }
                }
            }
            .padding(12)
            .frame(minHeight: 88)
            .background(DS.C.sur)
            .cornerRadius(DS.R.card)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warenkorb (rechts)

private struct CartPanel: View {
    let tableName:  String?
    let orderId:    Int?
    let onRemove:   (Int) async -> Void
    let onBezahlen: () -> Void

    @EnvironmentObject var orderStore: OrderStore
    @Environment(\.colorScheme) private var colorScheme

    private var order: OrderDetail? { orderStore.selectedOrder }
    private var items: [OrderItem]  { order?.items ?? [] }
    private var total: Int          { order?.totalCents ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(tableName ?? "Schnellkasse")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                if orderStore.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
                alignment: .bottom
            )

            // Items
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cart")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(DS.C.text2)
                    Text("Noch keine Positionen")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Text("Produkt antippen um es hinzuzufügen.")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            CartItemRow(item: item) {
                                Task { await onRemove(item.id) }
                            }
                        }
                    }
                    .padding(12)
                }
            }

            // Footer: Total + Bezahlen
            if !items.isEmpty {
                CartFooter(total: total, onBezahlen: onBezahlen)
            }
        }
        .background(DS.C.bg)
    }
}

private struct CartItemRow: View {
    let item:     OrderItem
    let onRemove: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Menge-Badge
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.C.sur2)
                    .frame(width: 26, height: 26)
                Text("\(item.quantity)×")
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(DS.C.text2)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.productName)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)

                // Modifier-Namen
                if !item.modifiers.isEmpty {
                    Text(item.modifiers.map { $0.name }.joined(separator: ", "))
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .lineLimit(1)
                }

                // Rabatt
                if item.discountCents > 0 {
                    Text("– \(formatCents(item.discountCents))")
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.freeText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCents(item.subtotalCents))
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)

                // Entfernen
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 20, height: 20)
                        .background(DS.C.sur2)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.C.sur)
        .cornerRadius(DS.R.pinRow)
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.pinRow)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
    }
}

private struct CartFooter: View {
    let total:       Int
    let onBezahlen:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            VStack(spacing: 10) {
                // Gesamtsumme
                HStack {
                    Text("Gesamt")
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    Text(formatCents(total))
                        .font(.jakarta(18, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)
                }

                Button(action: onBezahlen) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Bezahlen")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.S.buttonHeight)
                }
                .background(DS.C.acc)
                .cornerRadius(DS.R.button)
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(DS.C.sur)
        }
    }
}

// MARK: - ModifierSheet (Placeholder — vollständige Implementierung folgt in ModifierSheet.swift)

private struct ModifierSelectionSheet: View {
    let product:   Product
    let onConfirm: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionIds: [Int] = []

    /// Alle Pflicht-Gruppen bereits abgedeckt?
    private var requiredGroupsSatisfied: Bool {
        product.modifierGroups
            .filter { $0.isRequired }
            .allSatisfy { group in
                group.options.contains { selectedOptionIds.contains($0.id) }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag Indicator
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 20)

                    // Produkt-Info
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                                .foregroundColor(DS.C.text)
                            Text(formatCents(product.priceCents))
                                .font(.jakarta(DS.T.loginBody, weight: .regular))
                                .foregroundColor(DS.C.acc)
                        }
                        Spacer()
                    }

                    // Modifier-Gruppen
                    ForEach(product.modifierGroups) { group in
                        ModifierGroupSection(
                            group:             group,
                            selectedOptionIds: $selectedOptionIds
                        )
                    }

                    Spacer().frame(height: 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button("Abbrechen") { dismiss() }
                            .font(.jakarta(DS.T.loginButton, weight: .medium))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.button)
                            .buttonStyle(.plain)

                        Button {
                            onConfirm(selectedOptionIds)
                            dismiss()
                        } label: {
                            Text("Hinzufügen")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        }
                        .background(requiredGroupsSatisfied ? DS.C.acc : DS.C.acc.opacity(0.4))
                        .cornerRadius(DS.R.button)
                        .disabled(!requiredGroupsSatisfied)
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: requiredGroupsSatisfied)
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

private struct ModifierGroupSection: View {
    let group:             ModifierGroup
    @Binding var selectedOptionIds: [Int]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 16)

            HStack(spacing: 6) {
                Text(group.name.uppercased())
                    .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.5)
                if group.isRequired {
                    Text("PFLICHT")
                        .font(.jakarta(8, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.C.accBg)
                        .cornerRadius(4)
                }
            }

            ForEach(group.options) { option in
                ModifierOptionRow(
                    option:            option,
                    isSelected:        selectedOptionIds.contains(option.id),
                    isSingleSelect:    group.maxSelections == 1,
                    onTap: {
                        toggleOption(option, group: group)
                    }
                )
            }
        }
    }

    private func toggleOption(_ option: ModifierOption, group: ModifierGroup) {
        let singleSelect = group.maxSelections == 1
        if singleSelect {
            // Alle Optionen dieser Gruppe deselektieren, dann neue wählen
            let groupOptionIds = group.options.map { $0.id }
            selectedOptionIds.removeAll { groupOptionIds.contains($0) }
            selectedOptionIds.append(option.id)
        } else {
            if selectedOptionIds.contains(option.id) {
                selectedOptionIds.removeAll { $0 == option.id }
            } else {
                selectedOptionIds.append(option.id)
            }
        }
    }
}

private struct ModifierOptionRow: View {
    let option:         ModifierOption
    let isSelected:     Bool
    let isSingleSelect: Bool
    let onTap:          () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkbox / Radio
                ZStack {
                    RoundedRectangle(cornerRadius: isSingleSelect ? 10 : 5)
                        .strokeBorder(
                            isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if isSelected {
                        RoundedRectangle(cornerRadius: isSingleSelect ? 7 : 3)
                            .fill(DS.C.acc)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(option.name)
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text)

                Spacer()

                if option.priceDeltaCents > 0 {
                    Text("+ \(formatCents(option.priceDeltaCents))")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? DS.C.accBg : DS.C.bg)
            .cornerRadius(DS.R.pinRow)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.pinRow)
                    .strokeBorder(
                        isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
}

// MARK: - Previews

#Preview("Leere Bestellung — Tisch 3") {
    OrderView(tableId: 3, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Mit Positionen") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.preview)
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.preview)
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

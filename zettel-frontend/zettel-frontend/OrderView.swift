// OrderView.swift
// cashbox — Bestellansicht: Produktkatalog (links) + Warenkorb (rechts)
// Wird als fullScreenCover aus TableOverviewView geöffnet.
// Design v3: Touch-first (Qty-Buttons 38pt+), keine Hover-Zustände,
// Beträge in Tabellenziffern.

import SwiftUI

// MARK: - Root

struct OrderView: View {
    let tableId:   Int?
    let tableName: String?

    @EnvironmentObject var orderStore:    OrderStore
    @EnvironmentObject var productStore:  ProductStore
    @EnvironmentObject var tableStore:    TableStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var currentOrderId: Int? = nil
    @State private var pendingProduct: Product? = nil
    @State private var error: AppError?
    @State private var showError = false
    @State private var showCancelConfirm = false
    @State private var showPaymentView = false
    @State private var paymentOrder: OrderDetail? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.C.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !networkMonitor.isOnline {
                        OfflineBanner()
                            .dsBannerTransition()
                    }

                    OTopBar(
                        tableName: tableName,
                        orderId:   currentOrderId,
                        onClose:   { dismiss() }
                    )

                    HStack(spacing: 0) {
                        OProductCatalog(onProductTap: handleProductTap)
                            .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(DS.C.brdAdaptive)
                            .frame(width: 1)

                        OCartPanel(
                            orderId:    currentOrderId,
                            onRemove:   removeItem,
                            onAdd:      addItemById,
                            onClear:    { showCancelConfirm = true },
                            onBezahlen: {
                                paymentOrder = orderStore.selectedOrder
                                if let id = tableId { tableStore.payingTableIds.insert(id) }
                                showPaymentView = true
                            }
                        )
                        .frame(width: 340)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(DS.M.base, value: networkMonitor.isOnline)
            .task {
                await productStore.loadProducts()
                await findOrLoadExistingOrder()
            }
            .sheet(item: $pendingProduct) { product in
                ModifierSelectionSheet(product: product) { selectedOptionIds in
                    Task { await addProductWithModifiers(product, optionIds: selectedOptionIds) }
                }
            }
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
            .navigationDestination(isPresented: $showPaymentView) {
                if let order = paymentOrder {
                    PaymentView(order: order, tableName: tableName)
                        .environmentObject(orderStore)
                        .environmentObject(networkMonitor)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .onChange(of: showPaymentView) {
                if !showPaymentView {
                    if let id = tableId { tableStore.payingTableIds.remove(id) }
                    paymentOrder = nil
                    if orderStore.selectedOrder == nil && currentOrderId != nil {
                        Task { await tableStore.loadTables() }
                        dismiss()
                    }
                }
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────

    private func findOrLoadExistingOrder() async {
        orderStore.clearSelection()
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
            pendingProduct = product
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

    private func addItemById(productId: Int) async {
        do {
            let orderId = try await ensureOrder()
            try await orderStore.addItem(orderId: orderId, productId: productId)
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
            await tableStore.loadTables()
            dismiss()
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func ensureOrder() async throws -> Int {
        if let id = currentOrderId { return id }
        let newOrder = try await orderStore.createOrder(tableId: tableId)
        currentOrderId = newOrder.id
        return newOrder.id
    }
}

// MARK: - Top Bar

private struct OTopBar: View {
    let tableName: String?
    let orderId:   Int?
    let onClose:   () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Links: Zurück zur Tischübersicht
            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .dsFont(.raw(15, weight: .semibold))
                    Text("Tische")
                        .dsFont(.bodyMed)
                }
                .foregroundColor(DS.C.accT)
                .padding(.horizontal, 16)
                .frame(height: DS.S.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            Spacer()

            // Mitte: Tisch-Name
            Text(tableName ?? "Schnellkasse")
                .dsFont(.bodyBold)
                .foregroundColor(DS.C.text)

            Spacer()

            // Rechts: Order-Nr
            HStack {
                if let id = orderId {
                    Text("Bestellung #\(id)")
                        .dsFont(.caption, monoDigits: true)
                        .foregroundColor(DS.C.text2)
                }
            }
            .frame(minWidth: 120, alignment: .trailing)
            .padding(.trailing, DS.S.pagePad)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

// MARK: - Produktkatalog (links)

private struct OProductCatalog: View {
    @EnvironmentObject var productStore: ProductStore
    let onProductTap: (Product) -> Void

    @State private var selectedCategoryId: Int? = nil

    private var filteredProducts: [Product] {
        productStore.products(for: selectedCategoryId)
    }

    var body: some View {
        VStack(spacing: 0) {
            OCategoryTabBar(
                categories:         productStore.categories,
                selectedCategoryId: $selectedCategoryId
            )

            if productStore.isLoading {
                // Skeleton im echten Katalog-Layout statt zentriertem Spinner
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        ForEach(0..<9, id: \.self) { _ in
                            DSSkeleton(height: 110, cornerRadius: DS.R.card)
                        }
                    }
                    .padding(16)
                }
            } else if filteredProducts.isEmpty {
                DSEmptyState(
                    icon: "tag.slash",
                    title: "Keine Produkte",
                    message: "Produkte können in der Produktverwaltung angelegt werden."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        ForEach(filteredProducts) { product in
                            OProductCard(product: product) { onProductTap(product) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(DS.C.bg)
    }
}

// MARK: - Category Tab Bar

private struct OCategoryTabBar: View {
    let categories: [ProductCategoryRef]
    @Binding var selectedCategoryId: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                OCategoryPill(
                    label: "Alle",
                    color: nil,
                    isActive: selectedCategoryId == nil
                ) {
                    withAnimation(DS.M.base) { selectedCategoryId = nil }
                }
                ForEach(categories) { cat in
                    OCategoryPill(
                        label: cat.name,
                        color: cat.color,
                        isActive: selectedCategoryId == cat.id
                    ) {
                        withAnimation(DS.M.base) {
                            selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
            alignment: .bottom
        )
    }
}

private struct OCategoryPill: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                if let hex = color {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .dsFont(.raw(15, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(isActive ? DS.C.acc : DS.C.sur2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isActive)
    }
}

// MARK: - Product Card

private struct OProductCard: View {
    let product: Product
    let onTap:   () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .dsFont(.raw(16, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let catName = product.category?.name {
                    Text(catName)
                        .dsFont(.raw(13, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(alignment: .center, spacing: 0) {
                    MoneyText(cents: product.priceCents, size: 17, weight: .bold)

                    Spacer()

                    if product.hasRequiredModifiers {
                        Text("Optionen")
                            .dsFont(.raw(12, weight: .semibold))
                            .foregroundColor(DS.C.accT)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DS.C.accBg))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.C.sur))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(OCardPressStyle())
    }
}

/// Press-Feedback: kurzes Aufleuchten der Akzent-Border + Zusammendrücken
private struct OCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

// MARK: - Warenkorb (rechts)

private struct OCartPanel: View {
    let orderId:    Int?
    let onRemove:   (Int) async -> Void
    let onAdd:      (Int) async -> Void
    let onClear:    () -> Void
    let onBezahlen: () -> Void

    @EnvironmentObject var orderStore: OrderStore

    private var order: OrderDetail? { orderStore.selectedOrder }
    private var items: [OrderItem]  { order?.items ?? [] }
    private var total: Int          { order?.totalCents ?? 0 }
    private var totalArticles: Int  { items.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bestellung")
                    .dsFont(.bodyBold)
                    .foregroundColor(DS.C.text)
                Spacer()
                if orderStore.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .padding(.trailing, 6)
                }
                if !items.isEmpty {
                    Button(action: onClear) {
                        Text("Stornieren")
                            .dsFont(.captionBold)
                            .foregroundColor(DS.C.dangerText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: DS.S.topbarHeight)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
                alignment: .bottom
            )

            // Items
            if items.isEmpty {
                OCartEmpty()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            OCartItemRow(
                                item:     item,
                                onRemove: { Task { await onRemove(item.id) } },
                                onAdd:    { Task { await onAdd(item.productId) } }
                            )
                            if item.id != items.last?.id {
                                Rectangle()
                                    .fill(DS.C.brdAdaptive)
                                    .frame(height: 1)
                                    .padding(.leading, 18)
                            }
                        }
                    }
                }
                .background(DS.C.sur)
            }

            // Footer
            if !items.isEmpty {
                OCartFooter(
                    itemCount:    items.count,
                    articleCount: totalArticles,
                    total:        total,
                    onBezahlen:   onBezahlen
                )
            }
        }
        .background(DS.C.sur)
    }
}

private struct OCartEmpty: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DS.C.sur2)
                    .frame(width: 56, height: 56)
                Image(systemName: "cart")
                    .dsFont(.raw(22, weight: .medium))
                    .foregroundColor(DS.C.text2)
            }
            Text("Noch keine Positionen")
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
            Text("Produkt links antippen, um zu starten.")
                .dsFont(.caption)
                .foregroundColor(DS.C.text2.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.sur)
    }
}

private struct OCartItemRow: View {
    let item:     OrderItem
    let onRemove: () -> Void
    let onAdd:    () -> Void

    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + Preis
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.productName)
                        .dsFont(.raw(15, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .lineLimit(1)

                    if !item.modifiers.isEmpty {
                        Text(item.modifiers.map { $0.name }.joined(separator: " · "))
                            .dsFont(.raw(13))
                            .foregroundColor(DS.C.text2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MoneyText(cents: item.subtotalCents, size: 15, weight: .semibold)
                    .fixedSize()
            }

            // Menge: − n +
            HStack(spacing: 8) {
                OQtyButton(
                    icon: "minus",
                    isDanger: item.quantity == 1,
                    accessibilityLabel: item.quantity == 1 ? "Position entfernen" : "Menge verringern",
                    onTap: {
                        // Letzte Einheit = Position verschwindet → kurze Rückfrage
                        if item.quantity == 1 { showRemoveConfirm = true } else { onRemove() }
                    }
                )

                Text("\(item.quantity)")
                    .dsFont(.raw(16, weight: .bold), monoDigits: true)
                    .foregroundColor(DS.C.text)
                    .frame(minWidth: 36, alignment: .center)
                    .accessibilityLabel("Menge \(item.quantity)")

                OQtyButton(icon: "plus", isDanger: false,
                           accessibilityLabel: "Menge erhöhen", onTap: onAdd)

                Spacer()
            }
            .confirmationDialog(
                "\"\(item.productName)\" entfernen?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Entfernen", role: .destructive) { onRemove() }
                Button("Behalten", role: .cancel) {}
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct OQtyButton: View {
    let icon:     String
    let isDanger: Bool
    var accessibilityLabel: String = ""
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isDanger && icon == "minus" ? "trash" : icon)
                .dsFont(.raw(14, weight: .semibold))
                .foregroundColor(isDanger ? DS.C.dangerText : DS.C.text)
                .frame(width: DS.S.qtyButton, height: DS.S.qtyButton)
                .background(
                    RoundedRectangle(cornerRadius: DS.R.control)
                        .fill(isDanger ? DS.C.dangerBg : DS.C.sur2)
                )
                // Trefferfläche ≥ 44pt — Optik bleibt 38pt
                .frame(width: DS.S.touchTarget, height: DS.S.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(OCardPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct OCartFooter: View {
    let itemCount:    Int
    let articleCount: Int
    let total:        Int
    let onBezahlen:   () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

            VStack(spacing: 14) {
                HStack {
                    Text("\(itemCount) Position\(itemCount == 1 ? "" : "en") · \(articleCount) Artikel")
                        .dsFont(.caption, monoDigits: true)
                        .foregroundColor(DS.C.text2)
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Gesamt")
                        .dsFont(.bodyBold)
                        .foregroundColor(DS.C.text)
                    Spacer()
                    MoneyText(cents: total, size: 26, weight: .bold)
                }

                Button(action: onBezahlen) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .dsFont(.raw(16, weight: .semibold))
                        Text("Bezahlen")
                    }
                }
                .buttonStyle(DSPrimaryButton())
            }
            .padding(18)
            .background(DS.C.sur)
        }
    }
}

// MARK: - ModifierSheet

private struct ModifierSelectionSheet: View {
    let product:   Product
    let onConfirm: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionIds: [Int] = []

    private var requiredGroupsSatisfied: Bool {
        product.modifierGroups
            .filter { $0.isRequired }
            .allSatisfy { group in
                group.options.contains { selectedOptionIds.contains($0.id) }
            }
    }

    /// Basispreis + alle ausgewählten Aufpreise
    private var totalCents: Int {
        let deltas = selectedOptionIds.compactMap { id -> Int? in
            for group in product.modifierGroups {
                if let opt = group.options.first(where: { $0.id == id }) {
                    return opt.priceDeltaCents
                }
            }
            return nil
        }
        return product.priceCents + deltas.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .dsFont(.heading)
                        .foregroundColor(DS.C.text)

                    Text("Basispreis \(euroString(product.priceCents))")
                        .dsFont(.sub, monoDigits: true)
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .dsFont(.raw(13, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DS.C.sur2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive),
                alignment: .bottom
            )

            // Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(product.modifierGroups) { group in
                        MGroupSection(
                            group:             group,
                            selectedOptionIds: $selectedOptionIds
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            // Footer
            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        DSSectionLabel(text: "Gesamtpreis")
                        MoneyText(cents: totalCents, size: 22, weight: .bold)
                        if !requiredGroupsSatisfied {
                            Text("Pflichtoptionen auswählen")
                                .dsFont(.caption)
                                .foregroundColor(DS.C.dangerText)
                        }
                    }

                    Spacer()

                    Button {
                        onConfirm(selectedOptionIds)
                        dismiss()
                    } label: {
                        Text("Hinzufügen")
                    }
                    .buttonStyle(DSPrimaryButton(height: 50, fullWidth: false))
                    .disabled(!requiredGroupsSatisfied)
                    .animation(DS.M.base, value: requiredGroupsSatisfied)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(DS.C.sur)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

private struct MGroupSection: View {
    let group:             ModifierGroup
    @Binding var selectedOptionIds: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Group header: name + badge
            HStack {
                Text(group.name)
                    .dsFont(.bodyBold)
                    .foregroundColor(DS.C.text)

                Spacer()

                if group.isRequired {
                    Text("Pflicht")
                        .dsFont(.captionBold)
                        .foregroundColor(DS.C.brassText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.C.brassBg))
                } else {
                    Text("Optional")
                        .dsFont(.captionBold)
                        .foregroundColor(DS.C.text2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.C.sur2))
                }
            }

            // Options
            VStack(spacing: 8) {
                ForEach(group.options) { option in
                    MOptionRow(
                        option:         option,
                        isSelected:     selectedOptionIds.contains(option.id),
                        isSingleSelect: group.maxSelections == 1,
                        onTap: { toggleOption(option, group: group) }
                    )
                }
            }
        }
    }

    private func toggleOption(_ option: ModifierOption, group: ModifierGroup) {
        let singleSelect = group.maxSelections == 1
        if singleSelect {
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

private struct MOptionRow: View {
    let option:         ModifierOption
    let isSelected:     Bool
    let isSingleSelect: Bool
    let onTap:          () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Radio / Checkbox — 22pt, klar erkennbar
                ZStack {
                    if isSingleSelect {
                        Circle()
                            .strokeBorder(
                                isSelected ? DS.C.acc : DS.C.brdAdaptive,
                                lineWidth: 2
                            )
                            .background(
                                Circle().fill(isSelected ? DS.C.acc : Color.clear)
                            )
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isSelected ? DS.C.acc : DS.C.brdAdaptive,
                                lineWidth: 2
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? DS.C.acc : Color.clear)
                            )
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .dsFont(.raw(11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 22, height: 22)

                Text(option.name)
                    .dsFont(.raw(16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(DS.C.text)

                Spacer()

                Text(option.priceDeltaCents > 0 ? "+ \(euroString(option.priceDeltaCents))" : "inklusive")
                    .dsFont(.raw(15, weight: .medium), monoDigits: true)
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .fill(isSelected ? DS.C.accBg : DS.C.sur)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(isSelected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.input))
            .animation(DS.M.fast, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Leere Bestellung — Tisch 3") {
    OrderView(tableId: 3, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(ProductStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Mit Positionen") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.preview)
        .environmentObject(ProductStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(ProductStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    OrderView(tableId: 1, tableName: "Tisch 1")
        .environmentObject(OrderStore.preview)
        .environmentObject(ProductStore.preview)
        .environmentObject(TableStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

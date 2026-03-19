// OrderView.swift
// cashbox — Bestellansicht: Produktkatalog (links) + Warenkorb (rechts)
// Wird als fullScreenCover aus TableOverviewView geöffnet.

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
    @Environment(\.colorScheme) private var colorScheme

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
                            .transition(.move(edge: .top).combined(with: .opacity))
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
                            .fill(DS.C.brdLight)
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
                        .frame(width: 300)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Links: Brand + Zurück
            Button(action: onClose) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                    }
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DS.C.acc)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "squareshape.split.2x2")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                        Text("Kassensystem")
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)

            Spacer()

            // Mitte: Tisch-Badge
            Text(tableName.map { "\($0)" } ?? "Schnellkasse")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(DS.C.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(DS.C.sur2)
                .cornerRadius(20)

            Spacer()

            // Rechts: Order-Nr + Loading
            HStack(spacing: 8) {
                if let id = orderId {
                    Text("Bestellung #\(id)")
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.accT)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.C.accBg)
                        .cornerRadius(20)
                }
            }
            .padding(.trailing, 20)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
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
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            } else if filteredProducts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(DS.C.text2)
                    Text("Keine Produkte")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text("Produkte können in den Einstellungen angelegt werden.")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        ForEach(filteredProducts) { product in
                            OProductCard(product: product) { onProductTap(product) }
                        }
                    }
                    .padding(16)
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
            HStack(spacing: 0) {
                OCategoryTab(
                    label: "Alle",
                    color: nil,
                    isActive: selectedCategoryId == nil
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedCategoryId = nil }
                }
                ForEach(categories) { cat in
                    OCategoryTab(
                        label: cat.name,
                        color: cat.color,
                        isActive: selectedCategoryId == cat.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategoryId = selectedCategoryId == cat.id ? nil : cat.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(DS.C.sur)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

private struct OCategoryTab: View {
    let label:    String
    let color:    String?
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    if let hex = color {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 8, height: 8)
                    }
                    Text(label)
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(isActive ? DS.C.accT : DS.C.text2)
                        .fixedSize()
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)

                // Active bottom border (2px)
                Rectangle()
                    .fill(isActive ? DS.C.acc : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Product Card

private struct OProductCard: View {
    let product: Product
    let onTap:   () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Zeile 1: Name + VAT-Badge
                HStack(alignment: .top, spacing: 6) {
                    Text(product.name)
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("19 %")
                        .font(.jakarta(9, weight: .semibold))
                        .foregroundColor(DS.C.warnText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.C.warnBg)
                        .cornerRadius(4)
                        .padding(.top, 1)
                        .fixedSize()
                }

                // Zeile 2: Subtitle (Kategoriename als Sub-Text)
                if let catName = product.category?.name {
                    Text(catName)
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .lineLimit(1)
                }

                // Zeile 3: Preis + Modifier-Hinweis
                HStack(alignment: .center, spacing: 0) {
                    Text(oFmtCents(product.priceCents))
                        .font(.jakarta(15, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.2)

                    Spacer()

                    if product.hasRequiredModifiers {
                        Text("Optionen")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.accT)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(DS.C.accBg)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(DS.C.sur)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered ? DS.C.acc.opacity(0.3) : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
    @Environment(\.colorScheme) private var colorScheme

    private var order: OrderDetail? { orderStore.selectedOrder }
    private var items: [OrderItem]  { order?.items ?? [] }
    private var total: Int          { order?.totalCents ?? 0 }
    private var vatCents: Int       { total * 19 / 119 }
    private var totalArticles: Int  { items.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bestellung")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                if orderStore.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .padding(.trailing, 6)
                }
                if !items.isEmpty {
                    Button("Leeren", action: onClear)
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.dangerText)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
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
                                    .fill(DS.C.brdLight)
                                    .frame(height: 1)
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
                    vatCents:     vatCents,
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
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.C.sur2)
                    .frame(width: 44, height: 44)
                Image(systemName: "cart")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(DS.C.text2)
            }
            Text("Noch keine Positionen")
                .font(.jakarta(12, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.sur)
    }
}

private struct OCartItemRow: View {
    let item:     OrderItem
    let onRemove: () -> Void
    let onAdd:    () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var removeHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Info: Name + Mods + Qty-Row
            VStack(alignment: .leading, spacing: 0) {
                Text(item.productName)
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)

                if !item.modifiers.isEmpty {
                    Text(item.modifiers.map { $0.name }.joined(separator: " · "))
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                // Qty-Buttons: − | num | +
                HStack(spacing: 6) {
                    OQtyButton(label: "−", isDanger: true, isHovered: removeHovered) {
                        onRemove()
                    }
                    .onHover { removeHovered = $0 }

                    Text("\(item.quantity)")
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .frame(minWidth: 16, alignment: .center)

                    OQtyButton(label: "+", isDanger: false, isHovered: false) {
                        onAdd()
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Preis (rechts)
            Text(oFmtCents(item.subtotalCents))
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text)
                .fixedSize()
                .padding(.top, 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct OQtyButton: View {
    let label:     String
    let isDanger:  Bool
    let isHovered: Bool
    let onTap:     () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hov = false

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(
                    isDanger && hov ? DS.C.dangerText :
                    hov ? DS.C.text : DS.C.text2
                )
                .frame(width: 22, height: 22)
                .background(
                    isDanger && hov ? DS.C.dangerBg :
                    hov ? DS.C.sur2 : Color.clear
                )
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isDanger && hov ? DS.C.dangerText.opacity(0.4) : DS.C.brd(colorScheme),
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.1), value: hov)
        }
        .buttonStyle(.plain)
        .onHover { hov = $0 }
    }
}

private struct OCartFooter: View {
    let itemCount:    Int
    let articleCount: Int
    let vatCents:     Int
    let total:        Int
    let onBezahlen:   () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            VStack(spacing: 10) {
                // Positionen-Zeile
                HStack {
                    Text("\(itemCount) Position\(itemCount == 1 ? "" : "en")")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text("\(articleCount) Artikel")
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }

                // MwSt-Zeile
                HStack {
                    Text("MwSt. 19 %")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(oFmtCents(vatCents))
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }

                // Gesamt-Trennlinie + Zeile
                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                HStack {
                    Text("Gesamt")
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    Text(oFmtCents(total))
                        .font(.jakarta(20, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)
                }

                // Notiz-Button
                Button("+ Notiz zur Bestellung") {}
                    .font(.jakarta(12, weight: .medium))
                    .foregroundColor(DS.C.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                    )
                    .buttonStyle(.plain)

                // Bezahlen-Button
                Button(action: onBezahlen) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Zur Kasse · \(oFmtCents(total))")
                            .font(.jakarta(14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .background(DS.C.acc)
                .cornerRadius(12)
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(DS.C.sur)
        }
    }
}

// MARK: - ModifierSheet

private struct ModifierSelectionSheet: View {
    let product:   Product
    let onConfirm: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.jakarta(16, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)

                    Text("Basispreis: \(oFmtCents(product.priceCents))\(requiredGroupsSatisfied ? "" : " · Bitte Pflichtfelder auswählen")")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                // Close button
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 28, height: 28)
                        .background(DS.C.sur)
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
                alignment: .bottom
            )

            // Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(product.modifierGroups) { group in
                        MGroupSection(
                            group:             group,
                            selectedOptionIds: $selectedOptionIds
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            // Footer
            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                HStack(alignment: .center) {
                    // Gesamtpreis links
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GESAMTPREIS")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .tracking(0.5)
                        Text(oFmtCents(totalCents))
                            .font(.jakarta(18, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .tracking(-0.3)
                        if !requiredGroupsSatisfied {
                            Text("Pflichtfelder auswählen")
                                .font(.jakarta(10, weight: .regular))
                                .foregroundColor(DS.C.dangerText)
                        }
                    }

                    Spacer()

                    // Hinzufügen rechts
                    Button {
                        onConfirm(selectedOptionIds)
                        dismiss()
                    } label: {
                        Text("Hinzufügen · \(oFmtCents(totalCents))")
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .frame(height: 42)
                    }
                    .background(requiredGroupsSatisfied ? DS.C.acc : DS.C.acc.opacity(0.4))
                    .cornerRadius(10)
                    .disabled(!requiredGroupsSatisfied)
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: requiredGroupsSatisfied)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
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
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)

                Spacer()

                if group.isRequired {
                    Text("Pflicht · \(group.maxSelections ?? 1) auswählen")
                        .font(.jakarta(10, weight: .semibold))
                        .foregroundColor(DS.C.dangerText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.C.dangerBg)
                        .cornerRadius(20)
                } else {
                    Text("Optional")
                        .font(.jakarta(10, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DS.C.sur2)
                        .cornerRadius(20)
                }
            }

            // Options
            VStack(spacing: 6) {
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Radio or Checkbox (18×18)
                ZStack {
                    if isSingleSelect {
                        // Radio
                        Circle()
                            .strokeBorder(
                                isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                                lineWidth: 2
                            )
                            .background(
                                Circle().fill(isSelected ? DS.C.acc : Color.clear)
                            )
                            .frame(width: 18, height: 18)
                        if isSelected {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 7, height: 7)
                        }
                    } else {
                        // Checkbox
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                isSelected ? DS.C.acc : DS.C.brd(colorScheme),
                                lineWidth: 2
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? DS.C.acc : Color.clear)
                            )
                            .frame(width: 18, height: 18)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 18, height: 18)

                // Name
                Text(option.name)
                    .font(.jakarta(13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text)

                Spacer()

                // Preis
                Text(option.priceDeltaCents > 0 ? "+ \(oFmtCents(option.priceDeltaCents))" : "inklusive")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? DS.C.accBg : (isHovered ? DS.C.bg : Color.clear))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? DS.C.acc : (isHovered ? DS.C.acc.opacity(0.25) : DS.C.brd(colorScheme)),
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Helpers

private let _oFmt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale = Locale(identifier: "de_DE")
    return f
}()

private func oFmtCents(_ cents: Int) -> String {
    let val = NSNumber(value: Double(cents) / 100.0)
    return (_oFmt.string(from: val) ?? "0,00") + " €"
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

// PaymentView.swift
// cashbox — Bezahlung: Bar / Karte / Gemischt

import SwiftUI

// MARK: - Root

struct PaymentView: View {
    let order:     OrderDetail
    let tableName: String?

    @EnvironmentObject var orderStore:     OrderStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum PayMode { case bar, karte, gemischt }
    @State private var payMode       = PayMode.bar
    @State private var barRaw        = ""   // Ziffernfolge in Cent, z.B. "5000" = 50,00 €
    @State private var isLoading     = false
    @State private var error:        AppError?
    @State private var showError     = false
    @State private var paymentResult: PaymentResult?
    @State private var showReceipt   = false

    private var total:        Int              { order.totalCents }
    private var vatBreakdown: VatBreakdownLocal { computeVat(order.items) }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                PTopBar(
                    tableName: tableName,
                    orderId:   order.id,
                    onClose:   { dismiss() }
                )

                HStack(spacing: 0) {
                    POrderSummary(order: order, vat: vatBreakdown)
                        .frame(width: 290)

                    Rectangle().fill(DS.C.brdLight).frame(width: 1)

                    PPaymentRight(
                        payMode:    $payMode,
                        barRaw:     $barRaw,
                        totalCents: total,
                        isLoading:  isLoading,
                        onPay:      { Task { await performPayment() } }
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
        .sheet(isPresented: $showReceipt) {
            if let result = paymentResult {
                ReceiptSummarySheet(
                    result:    result,
                    tableName: tableName,
                    onDone:    { showReceipt = false; dismiss() }
                )
                .presentationDetents([.large])
            }
        }
        .onChange(of: payMode) { barRaw = "" }
    }

    // MARK: - Actions

    private func performPayment() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await orderStore.pay(orderId: order.id, payments: buildPayments())
            paymentResult = result
            showReceipt   = true
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }

    private func buildPayments() -> [PaymentItem] {
        switch payMode {
        case .bar:
            return [PaymentItem(method: .cash, amountCents: total)]
        case .karte:
            return [PaymentItem(method: .card, amountCents: total)]
        case .gemischt:
            let barC  = Int(barRaw) ?? 0
            let cardC = total - barC
            var out: [PaymentItem] = []
            if barC  > 0 { out.append(PaymentItem(method: .cash, amountCents: barC)) }
            if cardC > 0 { out.append(PaymentItem(method: .card, amountCents: cardC)) }
            return out
        }
    }
}

// MARK: - Top Bar

private struct PTopBar: View {
    let tableName: String?
    let orderId:   Int
    let onClose:   () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
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
                Button(action: onClose) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Zurück")
                            .font(.jakarta(12, weight: .semibold))
                    }
                    .foregroundColor(DS.C.text2)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 20)

            Spacer()

            Text(tableName ?? "Schnellkasse")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(DS.C.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(DS.C.sur2)
                .cornerRadius(20)

            Spacer()

            Text("Bestellung #\(orderId)")
                .font(.jakarta(11, weight: .semibold))
                .foregroundColor(DS.C.accT)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.C.accBg)
                .cornerRadius(20)
                .padding(.trailing, 20)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

// MARK: - Order Summary (links, 290px)

private struct VatBreakdownLocal {
    let vat7NetCents:  Int
    let vat7TaxCents:  Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    var has7:  Bool { vat7NetCents  + vat7TaxCents  > 0 }
    var has19: Bool { vat19NetCents + vat19TaxCents > 0 }
}

private func computeVat(_ items: [OrderItem]) -> VatBreakdownLocal {
    var v7n = 0, v7t = 0, v19n = 0, v19t = 0
    for item in items {
        let gross = item.subtotalCents
        let is7   = item.vatRate == "7"
        let net   = Int((Double(gross * 100) / Double(is7 ? 107 : 119)).rounded())
        let tax   = gross - net
        if is7 { v7n += net; v7t += tax } else { v19n += net; v19t += tax }
    }
    return VatBreakdownLocal(
        vat7NetCents: v7n, vat7TaxCents: v7t,
        vat19NetCents: v19n, vat19TaxCents: v19t
    )
}

private struct POrderSummary: View {
    let order: OrderDetail
    let vat:   VatBreakdownLocal
    @Environment(\.colorScheme) private var cs

    private var nettoCents:    Int { vat.vat19NetCents + vat.vat7NetCents }
    private var vatTotalCents: Int { vat.vat19TaxCents + vat.vat7TaxCents }
    private var itemCount:     Int { order.items.count }
    private var tableLabel:    String {
        order.table?.name ?? "Schnellkasse"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Bestellübersicht")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("\(tableLabel) · \(itemCount) Position\(itemCount == 1 ? "" : "en")")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Items
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(order.items) { item in
                        POSItemRow(item: item)
                        if item.id != order.items.last?.id {
                            Rectangle().fill(DS.C.brdLight).frame(height: 1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(DS.C.bg)

            // Totals footer
            VStack(spacing: 5) {
                HStack {
                    Text("Netto")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(pFmt(nettoCents))
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
                HStack {
                    Text("MwSt. 19 %")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(pFmt(vatTotalCents))
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
                Rectangle().fill(DS.C.brdLight).frame(height: 1).padding(.vertical, 3)
                HStack {
                    Text("Gesamt")
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    Text(pFmt(order.totalCents))
                        .font(.jakarta(20, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
        .background(DS.C.bg)
    }
}

private struct POSItemRow: View {
    let item: OrderItem
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
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
                        .padding(.top, 1)
                }
                Text("\(item.quantity)×")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .padding(.top, 1)
            }
            Spacer()
            Text(pFmt(item.subtotalCents))
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Payment Right Panel

private struct PPaymentRight: View {
    @Binding var payMode:   PaymentView.PayMode
    @Binding var barRaw:    String
    let totalCents: Int
    let isLoading:  Bool
    let onPay:      () -> Void

    private var barCents:       Int  { Int(barRaw) ?? 0 }
    private var cardCents:      Int  { max(0, totalCents - barCents) }
    private var canPayBar:      Bool { barCents >= totalCents }
    private var canPayGemischt: Bool { barCents > 0 && barCents <= totalCents }
    private var canPay: Bool {
        switch payMode {
        case .bar:      return canPayBar
        case .karte:    return true
        case .gemischt: return canPayGemischt
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                PMethodGrid(payMode: $payMode)

                switch payMode {
                case .bar:
                    PBarView(
                        totalCents: totalCents,
                        barRaw:     $barRaw,
                        canPay:     canPayBar,
                        isLoading:  isLoading,
                        onPay:      onPay
                    )
                case .karte:
                    PKarteView(
                        totalCents: totalCents,
                        isLoading:  isLoading,
                        onPay:      onPay
                    )
                case .gemischt:
                    PGemischtView(
                        totalCents: totalCents,
                        barRaw:     $barRaw,
                        cardCents:  cardCents,
                        canPay:     canPayGemischt,
                        isLoading:  isLoading,
                        onPay:      onPay
                    )
                }
            }
            .padding(18)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Method Grid

private struct PMethodGrid: View {
    @Binding var payMode: PaymentView.PayMode

    var body: some View {
        HStack(spacing: 8) {
            PMethodCard(icon: "banknote", label: "Barzahlung",   isSelected: payMode == .bar)      { withAnimation(.easeInOut(duration: 0.15)) { payMode = .bar } }
            PMethodCard(icon: "creditcard", label: "Kartenzahlung", isSelected: payMode == .karte)  { withAnimation(.easeInOut(duration: 0.15)) { payMode = .karte } }
            PMethodCard(icon: "arrow.left.arrow.right", label: "Gemischt", isSelected: payMode == .gemischt) { withAnimation(.easeInOut(duration: 0.15)) { payMode = .gemischt } }
        }
    }
}

private struct PMethodCard: View {
    let icon:       String
    let label:      String
    let isSelected: Bool
    let onTap:      () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? DS.C.acc.opacity(0.15) : DS.C.sur2)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                }
                Text(label)
                    .font(.jakarta(11, weight: .semibold))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(isSelected ? DS.C.accBg : DS.C.sur)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? DS.C.acc : DS.C.brd(cs), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bar View

private struct PBarView: View {
    let totalCents: Int
    @Binding var barRaw: String
    let canPay:    Bool
    let isLoading: Bool
    let onPay:     () -> Void
    @Environment(\.colorScheme) private var cs

    private var barCents:    Int  { Int(barRaw) ?? 0 }
    private var changeCents: Int  { barCents - totalCents }
    private var isExact:     Bool { !barRaw.isEmpty && changeCents == 0 }
    private var isOver:      Bool { !barRaw.isEmpty && changeCents > 0 }
    private var isUnder:     Bool { !barRaw.isEmpty && changeCents < 0 }

    private var givenColor: Color {
        if barRaw.isEmpty { return DS.C.text2 }
        if isExact { return DS.C.acc }
        if isOver  { return DS.C.freeText }
        return DS.C.dangerText
    }
    private var changeText: String {
        if barRaw.isEmpty { return "—" }
        if isExact { return pFmt(0) }
        if isOver  { return pFmt(changeCents) }
        return "\(pFmt(-changeCents)) fehlt"
    }
    private var changeColor: Color {
        if barRaw.isEmpty || isExact { return DS.C.text2 }
        if isOver { return DS.C.freeText }
        return DS.C.dangerText
    }
    private var confirmLabel: String {
        if barRaw.isEmpty { return "Betrag eingeben" }
        if isExact { return "Zahlung abschließen · Passend" }
        if isOver  { return "Zahlung abschließen · Wechselgeld \(pFmt(changeCents))" }
        return "Betrag unvollständig"
    }
    private var quickAmounts: [Int] {
        var set = Set<Int>()
        set.insert(totalCents)
        for div in [500, 1000, 2000, 5000, 10000] {
            let r = ((totalCents + div - 1) / div) * div
            if r >= totalCents && r < totalCents * 5 / 2 { set.insert(r) }
        }
        return set.sorted()
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                // Amount top
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZU ZAHLEN")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .tracking(0.5)
                        Text(pFmt(totalCents))
                            .font(.jakarta(13, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("GEGEBEN")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .tracking(0.5)
                        Text(barRaw.isEmpty ? "—" : pFmt(barCents))
                            .font(.jakarta(26, weight: .semibold))
                            .foregroundColor(givenColor)
                            .tracking(-0.5)
                            .animation(.easeInOut(duration: 0.1), value: givenColor.description)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // Quick amounts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            let exact = (amount == totalCents)
                            Button { barRaw = String(amount) } label: {
                                Text(exact ? "\(pFmt(amount)) ✓" : pFmt(amount))
                                    .font(.jakarta(11, weight: .semibold))
                                    .foregroundColor(exact ? DS.C.accT : DS.C.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(exact ? DS.C.accBg : Color.clear)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(exact ? DS.C.acc : DS.C.brd(cs), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // Wechselgeld row
                HStack {
                    Text("Wechselgeld")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(changeText)
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(changeColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // Numpad
                PNumpad { key in
                    if key == "del" { if !barRaw.isEmpty { barRaw.removeLast() } }
                    else if barRaw.count < 8 { barRaw += key }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .background(DS.C.sur)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.C.brd(cs), lineWidth: 1))

            PConfirmBtn(enabled: canPay, isLoading: isLoading, label: confirmLabel, onTap: onPay)
        }
    }
}

// MARK: - Karte View

private struct PKarteView: View {
    let totalCents: Int
    let isLoading:  Bool
    let onPay:      () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DS.C.accBg)
                            .frame(width: 56, height: 56)
                        Image(systemName: "creditcard")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(DS.C.accT)
                    }
                    Text(pFmt(totalCents))
                        .font(.jakarta(32, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.5)
                    Text("Karte am Terminal vorzeigen.\nZahlung wird direkt vom Terminal bestätigt.")
                        .font(.jakarta(12, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                HStack(spacing: 10) {
                    PKartePulse()
                    Text("Warte auf Kartenzahlung …")
                        .font(.jakarta(12, weight: .medium))
                        .foregroundColor(DS.C.warnText)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(DS.C.sur)
            }
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.C.brd(cs), lineWidth: 1))

            PConfirmBtn(
                enabled:   true,
                isLoading: isLoading,
                label:     "Kartenzahlung bestätigen",
                onTap:     onPay
            )
        }
    }
}

private struct PKartePulse: View {
    @State private var opacity: Double = 1.0
    var body: some View {
        Circle()
            .fill(DS.C.warnText)
            .frame(width: 10, height: 10)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    opacity = 0.3
                }
            }
    }
}

// MARK: - Gemischt View

private struct PGemischtView: View {
    let totalCents: Int
    @Binding var barRaw: String
    let cardCents:  Int
    let canPay:     Bool
    let isLoading:  Bool
    let onPay:      () -> Void
    @Environment(\.colorScheme) private var cs

    private var barCents:   Int    { Int(barRaw) ?? 0 }
    private var isOverflow: Bool   { barCents > totalCents }
    private var barPct:     Double { totalCents > 0 ? min(1.0, Double(barCents) / Double(totalCents)) : 0 }
    private var barPctInt:  Int    { Int(barPct * 100) }

    private var confirmLabel: String {
        if barRaw.isEmpty { return "Bar-Betrag eingeben" }
        if isOverflow     { return "Bar-Betrag zu hoch" }
        return "Zahlung abschließen · \(pFmt(barCents)) bar + \(pFmt(cardCents)) Karte"
    }
    private var quickAmounts: [Int] {
        [1000, 2000, 2500, 3000, 5000].filter { $0 <= totalCents }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                // Total row
                HStack {
                    Text("Zu zahlen gesamt")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(pFmt(totalCents))
                        .font(.jakarta(16, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // 2-col split
                HStack(spacing: 0) {
                    // Bar (active/manual)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(DS.C.sur2)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "banknote")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DS.C.text2)
                            }
                            Text("Bar")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.accT)
                        }
                        HStack {
                            Spacer()
                            Text(barRaw.isEmpty ? "0,00" : pFmt(barCents).replacingOccurrences(of: " €", with: ""))
                                .font(.jakarta(16, weight: .semibold))
                                .foregroundColor(isOverflow ? DS.C.dangerText : DS.C.text)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(DS.C.bg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DS.C.acc, lineWidth: 1.5)
                        )
                        Text(isOverflow ? "Bar-Betrag zu hoch" : (barCents > 0 ? "\(pFmt(barCents)) bar" : "Betrag eingeben"))
                            .font(.jakarta(10, weight: .regular))
                            .foregroundColor(isOverflow ? DS.C.dangerText : (barCents > 0 ? DS.C.accT : DS.C.text2))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(DS.C.brdLight).frame(width: 1)

                    // Karte (auto)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(DS.C.sur2)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "creditcard")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(DS.C.text2)
                            }
                            Text("Karte")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        HStack {
                            Spacer()
                            Text(!barRaw.isEmpty && !isOverflow ? pFmt(cardCents).replacingOccurrences(of: " €", with: "") : "—")
                                .font(.jakarta(16, weight: .semibold))
                                .foregroundColor(DS.C.text2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(DS.C.sur2)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(DS.C.brd(cs), lineWidth: 1.5)
                        )
                        Text("Wird automatisch berechnet")
                            .font(.jakarta(10, weight: .regular))
                            .foregroundColor(DS.C.accT)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                }
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // Bar chart
                VStack(spacing: 8) {
                    Text("AUFTEILUNG")
                        .font(.jakarta(9, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.C.sur2)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.C.acc)
                                .frame(width: max(0, geo.size.width * barPct), height: 8)
                        }
                    }
                    .frame(height: 8)
                    .animation(.easeInOut(duration: 0.2), value: barPct)
                    HStack {
                        Text("Bar: \(barPctInt) %")
                            .font(.jakarta(10, weight: .regular))
                            .foregroundColor(DS.C.text2)
                        Spacer()
                        Text("Karte: \(100 - barPctInt) %")
                            .font(.jakarta(10, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                // Quick amounts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            Button { barRaw = String(amount) } label: {
                                Text("\(amount / 100) € bar")
                                    .font(.jakarta(11, weight: .semibold))
                                    .foregroundColor(DS.C.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.clear)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(DS.C.brd(cs), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)

                PNumpad { key in
                    if key == "del" { if !barRaw.isEmpty { barRaw.removeLast() } }
                    else if barRaw.count < 7 { barRaw += key }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(DS.C.sur)
            }
            .background(DS.C.sur)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.C.brd(cs), lineWidth: 1))

            PConfirmBtn(enabled: canPay, isLoading: isLoading, label: confirmLabel, onTap: onPay)
        }
    }
}

// MARK: - Numpad

private struct PNumpad: View {
    let onTap: (String) -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
            spacing: 6
        ) {
            ForEach(["1","2","3","4","5","6","7","8","9"], id: \.self) { key in
                PNumKeyBtn(label: key, cs: cs) { onTap(key) }
                    .frame(height: 46)
            }
            PNumKeyBtn(label: "0", cs: cs) { onTap("0") }
                .gridCellColumns(2)
                .frame(height: 46)
            PNumDelBtn(cs: cs) { onTap("del") }
                .frame(height: 46)
        }
    }
}

private struct PNumKeyBtn: View {
    let label:  String
    let cs:     ColorScheme
    let onTap:  () -> Void
    @State private var hov = false

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.jakarta(16, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hov ? DS.C.sur2 : DS.C.sur)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.C.brd(cs), lineWidth: 1))
                .animation(.easeInOut(duration: 0.08), value: hov)
        }
        .buttonStyle(.plain)
        .onHover { hov = $0 }
    }
}

private struct PNumDelBtn: View {
    let cs:    ColorScheme
    let onTap: () -> Void
    @State private var hov = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "delete.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(hov ? DS.C.dangerText : DS.C.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hov ? DS.C.dangerBg : DS.C.sur2)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(hov ? DS.C.dangerText.opacity(0.4) : DS.C.brd(cs), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.08), value: hov)
        }
        .buttonStyle(.plain)
        .onHover { hov = $0 }
    }
}

// MARK: - Confirm Button

private struct PConfirmBtn: View {
    let enabled:   Bool
    let isLoading: Bool
    let label:     String
    let onTap:     () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if isLoading {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text(label)
                            .font(.jakarta(13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .background(enabled ? DS.C.acc : DS.C.acc.opacity(0.35))
        .cornerRadius(12)
        .disabled(!enabled || isLoading)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: enabled)
    }
}

// MARK: - Receipt Summary Sheet

private struct ReceiptSummarySheet: View {
    let result:    PaymentResult
    let tableName: String?
    let onDone:    () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFullReceipt = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DS.C.accBg)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                }
                Text("Bezahlung erfolgreich")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Bon #\(result.receiptNumber)\(tableName.map { " · \($0)" } ?? "")")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        RSHeader("ZAHLUNG")
                        VStack(spacing: 6) {
                            ForEach(result.payments.indices, id: \.self) { i in
                                let p = result.payments[i]
                                HStack {
                                    HStack(spacing: 7) {
                                        Image(systemName: p.method.icon)
                                            .font(.system(size: 13))
                                            .foregroundColor(DS.C.text2)
                                        Text(p.method.displayName)
                                            .font(.jakarta(DS.T.loginBody, weight: .regular))
                                            .foregroundColor(DS.C.text)
                                    }
                                    Spacer()
                                    Text(pFmt(p.amountCents))
                                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                                        .foregroundColor(DS.C.text)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(DS.C.sur)
                                .cornerRadius(DS.R.pinRow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.R.pinRow)
                                        .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        RSHeader("MWST-AUFSCHLÜSSELUNG")
                        VStack(spacing: 6) {
                            let has7  = result.vat7NetCents  + result.vat7TaxCents  > 0
                            let has19 = result.vat19NetCents + result.vat19TaxCents > 0
                            if has7 {
                                RSVatRow(label: "7 % Netto",  value: result.vat7NetCents)
                                RSVatRow(label: "7 % Steuer", value: result.vat7TaxCents, dim: true)
                            }
                            if has19 {
                                RSVatRow(label: "19 % Netto",  value: result.vat19NetCents)
                                RSVatRow(label: "19 % Steuer", value: result.vat19TaxCents, dim: true)
                            }
                            Divider()
                            RSVatRow(label: "Gesamt (Brutto)", value: result.totalGrossCents, bold: true)
                        }
                        .padding(12)
                        .background(DS.C.sur)
                        .cornerRadius(DS.R.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.card)
                                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                        )
                    }

                    if result.tsePending {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13))
                                .foregroundColor(DS.C.text2)
                            Text("TSE-Signatur ausstehend — wird nachgeholt sobald online")
                                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                .foregroundColor(DS.C.text2)
                        }
                        .padding(12)
                        .background(DS.C.sur2)
                        .cornerRadius(DS.R.card)
                    }
                }
                .padding(20)
            }

            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                VStack(spacing: 8) {
                    Button {
                        showFullReceipt = true
                    } label: {
                        Text("Bon anzeigen")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(DS.C.acc)
                            .frame(maxWidth: .infinity)
                            .frame(height: DS.S.buttonHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.R.button)
                                    .strokeBorder(DS.C.acc, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onDone) {
                        Text("Fertig")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: DS.S.buttonHeight)
                    }
                    .background(DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
            .background(DS.C.sur)
        }
        .background(DS.C.sur)
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showFullReceipt) {
            ReceiptView(receiptId: result.receiptId)
        }
    }
}

private struct RSHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
            .foregroundColor(DS.C.text2)
            .tracking(0.5)
    }
}

private struct RSVatRow: View {
    let label: String
    let value: Int
    var dim:   Bool = false
    var bold:  Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
            Spacer()
            Text(pFmt(value))
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.acc : (dim ? DS.C.text2 : DS.C.text))
        }
    }
}

// MARK: - Helpers

private let _pFmt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale = Locale(identifier: "de_DE")
    return f
}()

private func pFmt(_ cents: Int) -> String {
    let val = NSNumber(value: Double(cents) / 100.0)
    return (_pFmt.string(from: val) ?? "0,00") + " €"
}

private func parseCents(_ text: String) -> Int {
    let cleaned = text
        .replacingOccurrences(of: "€", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ",", with: ".")
        .trimmingCharacters(in: .whitespaces)
    guard let value = Double(cleaned) else { return 0 }
    return Int((value * 100).rounded())
}

// MARK: - Preview Factory

private extension OrderDetail {
    static var previewSample: OrderDetail {
        return OrderDetail(
            id: 42, status: .open, isTakeaway: false,
            createdAt: "2026-03-16T10:00:00.000Z", closedAt: nil,
            sessionId: 1, openedByName: "Niko",
            table: OrderTable(id: 3, name: "Tisch 3"),
            items: [
                OrderItem(
                    id: 1, productId: 1, productName: "Shisha Premium",
                    productPriceCents: 2500, vatRate: "19", quantity: 1,
                    subtotalCents: 2500, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: [
                        OrderItemModifier(modifierOptionId: 2, name: "Fumari Ambrosia", priceDeltaCents: 0)
                    ]
                ),
                OrderItem(
                    id: 2, productId: 2, productName: "Shisha Standard",
                    productPriceCents: 1900, vatRate: "19", quantity: 1,
                    subtotalCents: 1900, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: [
                        OrderItemModifier(modifierOptionId: 3, name: "Al Fakher Mint", priceDeltaCents: 0)
                    ]
                ),
                OrderItem(
                    id: 3, productId: 4, productName: "Kohle Nachfüllen",
                    productPriceCents: 300, vatRate: "19", quantity: 2,
                    subtotalCents: 600, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: []
                ),
            ],
            totalCents: 5000
        )
    }
}

// MARK: - Previews

#Preview("Bar — Tisch 3") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

#Preview("Offline") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.previewOffline)
}

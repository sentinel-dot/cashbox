// PaymentView.swift
// cashbox — Bezahlung: Bar / Karte / Gemischt
// Design v3: großer Numpad (60pt-Tasten), Beträge in Tabellenziffern,
// MwSt-Aufschlüsselung getrennt nach 7 % und 19 %.

import SwiftUI

// MARK: - Root

struct PaymentView: View {
    let order:     OrderDetail
    let tableName: String?

    @EnvironmentObject var orderStore:     OrderStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    enum PayMode { case bar, karte, gemischt }
    @State private var payMode       = PayMode.bar
    @State private var barRaw        = ""   // Ziffernfolge in Cent, z.B. "5000" = 50,00 €
    // „Passend" ist der häufigste Fall → Betrag vorbelegen; erste Eingabe ersetzt ihn
    @State private var barIsPrefill  = false
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
                        .dsBannerTransition()
                }

                PTopBar(
                    tableName: tableName,
                    orderId:   order.id,
                    onClose:   { dismiss() }
                )

                HStack(spacing: 0) {
                    POrderSummary(order: order, vat: vatBreakdown)
                        .frame(width: 320)

                    Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)

                    PPaymentRight(
                        payMode:      $payMode,
                        barRaw:       $barRaw,
                        barIsPrefill: $barIsPrefill,
                        totalCents:   total,
                        isLoading:    isLoading,
                        onPay:        { Task { await performPayment() } }
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
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
        .onAppear { applyBarPrefill() }
        .onChange(of: payMode) { applyBarPrefill() }
    }

    /// Bar-Modus: Betrag mit „passend" vorbelegen — 0-Tap-Default für den häufigsten Fall
    private func applyBarPrefill() {
        if payMode == .bar {
            barRaw = String(total)
            barIsPrefill = true
        } else {
            barRaw = ""
            barIsPrefill = false
        }
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

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .dsFont(.raw(15, weight: .semibold))
                    Text("Bestellung")
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

            Text("Bezahlen · \(tableName ?? "Schnellkasse")")
                .dsFont(.bodyBold)
                .foregroundColor(DS.C.text)

            Spacer()

            Text("Bestellung #\(orderId)")
                .dsFont(.caption, monoDigits: true)
                .foregroundColor(DS.C.text2)
                .frame(minWidth: 120, alignment: .trailing)
                .padding(.trailing, DS.S.pagePad)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

// MARK: - Order Summary (links)

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

    private var nettoCents:    Int { vat.vat19NetCents + vat.vat7NetCents }
    private var itemCount:     Int { order.items.count }
    private var tableLabel:    String {
        order.table?.name ?? "Schnellkasse"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Bestellübersicht")
                    .dsFont(.bodyBold)
                    .foregroundColor(DS.C.text)
                Text("\(tableLabel) · \(itemCount) Position\(itemCount == 1 ? "" : "en")")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)

            // Items
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(order.items) { item in
                        POSItemRow(item: item)
                        if item.id != order.items.last?.id {
                            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(DS.C.sur)

            // Totals footer
            VStack(spacing: 8) {
                PSummaryRow(label: "Netto", cents: nettoCents)
                if vat.has7 {
                    PSummaryRow(label: "MwSt. 7 %", cents: vat.vat7TaxCents)
                }
                if vat.has19 {
                    PSummaryRow(label: "MwSt. 19 %", cents: vat.vat19TaxCents)
                }
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1).padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline) {
                    Text("Gesamt")
                        .dsFont(.bodyBold)
                        .foregroundColor(DS.C.text)
                    Spacer()
                    MoneyText(cents: order.totalCents, size: 24, weight: .bold)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(DS.C.sur)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
        .background(DS.C.sur)
    }
}

private struct PSummaryRow: View {
    let label: String
    let cents: Int
    var body: some View {
        HStack {
            Text(label)
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
            Spacer()
            Text(euroString(cents))
                .dsFont(.money(15, weight: .medium))
                .foregroundColor(DS.C.text)
        }
    }
}

private struct POSItemRow: View {
    let item: OrderItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(item.quantity)×")
                .dsFont(.money(15, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .frame(width: 30, alignment: .leading)

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
            Spacer()
            MoneyText(cents: item.subtotalCents, size: 15, weight: .semibold)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

// MARK: - Payment Right Panel

private struct PPaymentRight: View {
    @Binding var payMode:      PaymentView.PayMode
    @Binding var barRaw:       String
    @Binding var barIsPrefill: Bool
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
            VStack(spacing: 16) {
                PMethodGrid(payMode: $payMode)

                switch payMode {
                case .bar:
                    PBarView(
                        totalCents: totalCents,
                        barRaw:     $barRaw,
                        isPrefill:  $barIsPrefill,
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
            .padding(DS.S.pagePad)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Method Grid

private struct PMethodGrid: View {
    @Binding var payMode: PaymentView.PayMode

    var body: some View {
        HStack(spacing: 10) {
            PMethodCard(icon: "banknote",  label: "Bar",      isSelected: payMode == .bar)      { withAnimation(DS.M.base) { payMode = .bar } }
            PMethodCard(icon: "creditcard", label: "Karte",    isSelected: payMode == .karte)    { withAnimation(DS.M.base) { payMode = .karte } }
            PMethodCard(icon: "arrow.left.arrow.right", label: "Gemischt", isSelected: payMode == .gemischt) { withAnimation(DS.M.base) { payMode = .gemischt } }
        }
    }
}

private struct PMethodCard: View {
    let icon:       String
    let label:      String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .dsFont(.raw(22, weight: .semibold))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text2)
                Text(label)
                    .dsFont(.raw(15, weight: .semibold))
                    .foregroundColor(isSelected ? DS.C.accT : DS.C.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .fill(isSelected ? DS.C.accBg : DS.C.sur)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(isSelected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
            .animation(DS.M.fast, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bar View

private struct PBarView: View {
    let totalCents: Int
    @Binding var barRaw: String
    @Binding var isPrefill: Bool
    let canPay:    Bool
    let isLoading: Bool
    let onPay:     () -> Void

    private var barCents:    Int  { Int(barRaw) ?? 0 }
    private var changeCents: Int  { barCents - totalCents }
    private var isExact:     Bool { !barRaw.isEmpty && changeCents == 0 }
    private var isOver:      Bool { !barRaw.isEmpty && changeCents > 0 }

    private var givenColor: Color {
        if barRaw.isEmpty { return DS.C.text2 }
        if isExact || isOver { return DS.C.accT }
        return DS.C.dangerText
    }
    private var changeText: String {
        if barRaw.isEmpty { return "—" }
        if isExact { return euroString(0) }
        if isOver  { return euroString(changeCents) }
        return "\(euroString(-changeCents)) fehlt"
    }
    private var changeColor: Color {
        if barRaw.isEmpty || isExact { return DS.C.text2 }
        if isOver { return DS.C.accT }
        return DS.C.dangerText
    }
    private var confirmLabel: String {
        if barRaw.isEmpty { return "Betrag eingeben" }
        if isExact { return "Zahlung abschließen · passend" }
        if isOver  { return "Abschließen · \(euroString(changeCents)) zurück" }
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
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                // Zu zahlen / Gegeben
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        DSSectionLabel(text: "Zu zahlen")
                        MoneyText(cents: totalCents, size: 22, weight: .bold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        DSSectionLabel(text: "Gegeben")
                        Text(barRaw.isEmpty ? "—" : euroString(barCents))
                            .dsFont(.moneyDisplay(34))
                            .foregroundColor(givenColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                // Schnellbeträge
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            let exact = (amount == totalCents)
                            Button { barRaw = String(amount); isPrefill = false } label: {
                                Text(exact ? "Passend" : euroString(amount))
                                    .dsFont(.money(15, weight: .semibold))
                                    .foregroundColor(exact ? DS.C.accT : DS.C.text)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(Capsule().fill(exact ? DS.C.accBg : DS.C.sur2))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                // Wechselgeld
                HStack {
                    Text("Wechselgeld")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(changeText)
                        .dsFont(.money(18, weight: .bold))
                        .foregroundColor(changeColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                // Numpad — erste Eingabe ersetzt den „passend"-Vorschlag
                PNumpad { key in
                    if key == "del" {
                        if isPrefill { barRaw = ""; isPrefill = false }
                        else if !barRaw.isEmpty { barRaw.removeLast() }
                    } else {
                        if isPrefill { barRaw = ""; isPrefill = false }
                        if barRaw.count < 8 { barRaw += key }
                    }
                }
                .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.sur))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))

            PConfirmBtn(enabled: canPay, isLoading: isLoading, label: confirmLabel, onTap: onPay)
        }
    }
}

// MARK: - Karte View

private struct PKarteView: View {
    let totalCents: Int
    let isLoading:  Bool
    let onPay:      () -> Void

    // Es gibt (Phase 1) keine Terminal-Integration — die Kasse erfasst die
    // Kartenzahlung nur. Damit unter Zeitdruck kein Bon vor der echten
    // Terminal-Genehmigung gebucht wird: explizite Bestätigung als Gate.
    @State private var terminalApproved = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(DS.C.accBg)
                            .frame(width: 64, height: 64)
                        Image(systemName: "creditcard")
                            .dsFont(.icon(26))
                            .foregroundColor(DS.C.accT)
                    }
                    MoneyText(cents: totalCents, size: 40, weight: .bold)
                    Text("Betrag am Kartenterminal eingeben und die Zahlung dort durchführen.\nDie Kasse erfasst die Zahlung nur — sie läuft über dein Terminal.")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .background(DS.C.sur)

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                Button {
                    withAnimation(DS.M.fast) { terminalApproved.toggle() }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: terminalApproved ? "checkmark.circle.fill" : "circle")
                            .dsFont(.icon(24))
                            .foregroundColor(terminalApproved ? DS.C.acc : DS.C.text2)
                        Text("Terminal hat die Zahlung genehmigt")
                            .dsFont(.bodyMed)
                            .foregroundColor(DS.C.text)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(terminalApproved ? DS.C.accBg : DS.C.sur)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(terminalApproved ? [.isButton, .isSelected] : .isButton)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))

            PConfirmBtn(
                enabled:   terminalApproved,
                isLoading: isLoading,
                label:     terminalApproved ? "Kartenzahlung erfassen" : "Erst am Terminal bestätigen",
                onTap:     onPay
            )
        }
        .onAppear { terminalApproved = false }
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

    private var barCents:   Int    { Int(barRaw) ?? 0 }
    private var isOverflow: Bool   { barCents > totalCents }

    private var confirmLabel: String {
        if barRaw.isEmpty { return "Bar-Betrag eingeben" }
        if isOverflow     { return "Bar-Betrag zu hoch" }
        return "Abschließen · \(euroString(barCents)) bar + \(euroString(cardCents)) Karte"
    }
    private var quickAmounts: [Int] {
        [1000, 2000, 2500, 3000, 5000].filter { $0 <= totalCents }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                // Gesamt
                HStack {
                    Text("Zu zahlen gesamt")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    MoneyText(cents: totalCents, size: 20, weight: .bold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                // Split: Bar (Eingabe) | Karte (Rest, automatisch)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "banknote")
                                .dsFont(.raw(15, weight: .semibold))
                                .foregroundColor(DS.C.accT)
                            Text("Bar")
                                .dsFont(.subBold)
                                .foregroundColor(DS.C.text)
                        }
                        Text(barRaw.isEmpty ? "—" : euroString(barCents))
                            .dsFont(.money(24, weight: .bold))
                            .foregroundColor(isOverflow ? DS.C.dangerText : DS.C.text)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(height: 44)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.bg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.R.control)
                                    .strokeBorder(isOverflow ? DS.C.danger : DS.C.acc, lineWidth: 1.5)
                            )
                        Text(isOverflow ? "Bar-Betrag über Gesamtsumme" : "Über Numpad eingeben")
                            .dsFont(.caption)
                            .foregroundColor(isOverflow ? DS.C.dangerText : DS.C.text2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard")
                                .dsFont(.raw(15, weight: .semibold))
                                .foregroundColor(DS.C.text2)
                            Text("Karte")
                                .dsFont(.subBold)
                                .foregroundColor(DS.C.text)
                        }
                        Text(!barRaw.isEmpty && !isOverflow ? euroString(cardCents) : "—")
                            .dsFont(.money(24, weight: .bold))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(height: 44)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.sur2))
                        Text("Restbetrag, automatisch")
                            .dsFont(.caption)
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                // Schnellbeträge
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            Button { barRaw = String(amount) } label: {
                                Text("\(amount / 100) € bar")
                                    .dsFont(.money(15, weight: .semibold))
                                    .foregroundColor(DS.C.text)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(Capsule().fill(DS.C.sur2))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

                PNumpad { key in
                    if key == "del" { if !barRaw.isEmpty { barRaw.removeLast() } }
                    else if barRaw.count < 7 { barRaw += key }
                }
                .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.sur))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))

            PConfirmBtn(enabled: canPay, isLoading: isLoading, label: confirmLabel, onTap: onPay)
        }
    }
}

// MARK: - Numpad

private struct PNumpad: View {
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(["1","2","3","4","5","6","7","8","9"], id: \.self) { key in
                PNumKeyBtn(label: key) { onTap(key) }
                    .frame(height: 60)
            }
            PNumKeyBtn(label: "0") { onTap("0") }
                .gridCellColumns(2)
                .frame(height: 60)
            PNumDelBtn { onTap("del") }
                .frame(height: 60)
        }
    }
}

private struct PNumKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .fill(configuration.isPressed ? DS.C.sur2 : DS.C.bg)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

private struct PNumKeyBtn: View {
    let label:  String
    let onTap:  () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            Text(label)
                .dsFont(.money(22, weight: .semibold))
                .foregroundColor(DS.C.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PNumKeyStyle())
    }
}

private struct PNumDelBtn: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            Image(systemName: "delete.left")
                .dsFont(.raw(19, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PNumKeyStyle())
        .accessibilityLabel("Letzte Ziffer löschen")
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
                            .dsFont(.raw(15, weight: .semibold))
                        Text(label)
                    }
                }
            }
        }
        .buttonStyle(DSPrimaryButton(height: 56))
        .disabled(!enabled || isLoading)
        .animation(DS.M.base, value: enabled)
    }
}

// MARK: - Receipt Summary Sheet

private struct ReceiptSummarySheet: View {
    let result:    PaymentResult
    let tableName: String?
    let onDone:    () -> Void
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

            VStack(spacing: 12) {
                DSSuccessCheckmark()
                Text("Zahlung erfolgreich")
                    .dsFont(.title)
                    .foregroundColor(DS.C.text)
                Text("Bon #\(result.receiptNumber)\(tableName.map { " · \($0)" } ?? "")")
                    .dsFont(.sub, monoDigits: true)
                    .foregroundColor(DS.C.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .onAppear { Haptics.success() }

            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        DSSectionLabel(text: "Zahlung")
                        VStack(spacing: 8) {
                            ForEach(result.payments.indices, id: \.self) { i in
                                let p = result.payments[i]
                                HStack {
                                    HStack(spacing: 9) {
                                        Image(systemName: p.method.icon)
                                            .dsFont(.raw(15))
                                            .foregroundColor(DS.C.text2)
                                        Text(p.method.displayName)
                                            .dsFont(.sub)
                                            .foregroundColor(DS.C.text)
                                    }
                                    Spacer()
                                    MoneyText(cents: p.amountCents, size: 15, weight: .semibold)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.sur))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.R.input)
                                        .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        DSSectionLabel(text: "MwSt-Aufschlüsselung")
                        VStack(spacing: 8) {
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
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.sur))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.card)
                                .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
                        )
                    }

                    if result.tsePending {
                        HStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath")
                                .dsFont(.raw(14))
                                .foregroundColor(DS.C.brassText)
                            Text("TSE-Signatur ausstehend — wird nachgeholt sobald online")
                                .dsFont(.caption)
                                .foregroundColor(DS.C.brassText)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.R.card).fill(DS.C.brassBg))
                    }
                }
                .padding(DS.S.pagePad)
            }
            .background(DS.C.bg)

            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                VStack(spacing: 10) {
                    Button("Bon anzeigen") { showFullReceipt = true }
                        .buttonStyle(DSSecondaryButton())

                    Button("Fertig", action: onDone)
                        .buttonStyle(DSPrimaryButton())
                }
                .padding(16)
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

private struct RSVatRow: View {
    let label: String
    let value: Int
    var dim:   Bool = false
    var bold:  Bool = false
    var body: some View {
        HStack {
            Text(label)
                .dsFont(.raw(15, weight: bold ? .semibold : .regular))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
            Spacer()
            Text(euroString(value))
                .dsFont(.money(15, weight: bold ? .bold : .medium))
                .foregroundColor(bold ? DS.C.accT : (dim ? DS.C.text2 : DS.C.text))
        }
    }
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

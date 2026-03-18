// PaymentView.swift
// cashbox — Bezahlung: Bar / Karte / Gemischt, MwSt-Aufschlüsselung, Bon-Zusammenfassung

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
    @State private var cashInputText = ""
    @State private var isLoading     = false
    @State private var error:        AppError?
    @State private var showError     = false
    @State private var paymentResult: PaymentResult?
    @State private var showReceipt   = false

    private var total:        Int             { order.totalCents }
    private var vatBreakdown: VatBreakdownLocal { computeVat(order.items) }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                PaymentTopBar(
                    tableName: tableName,
                    orderId:   order.id,
                    onClose:   { dismiss() }
                )

                HStack(spacing: 0) {
                    OrderSummaryPanel(order: order, vat: vatBreakdown)
                        .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(DS.C.brdLight)
                        .frame(width: 1)

                    PaymentPanel(
                        payMode:    $payMode,
                        cashInput:  $cashInputText,
                        totalCents: total,
                        isLoading:  isLoading,
                        onPay:      { Task { await performPayment() } }
                    )
                    .frame(width: 340)
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
    }

    // MARK: - Actions

    private func performPayment() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items  = buildPayments()
            let result = try await orderStore.pay(orderId: order.id, payments: items)
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
            let cash = parseCents(cashInputText)
            let card = total - cash
            var out: [PaymentItem] = []
            if cash > 0 { out.append(PaymentItem(method: .cash, amountCents: cash)) }
            if card > 0 { out.append(PaymentItem(method: .card, amountCents: card)) }
            return out
        }
    }
}

// MARK: - Top Bar

private struct PaymentTopBar: View {
    let tableName: String?
    let orderId:   Int
    let onClose:   () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
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

            VStack(alignment: .leading, spacing: 1) {
                Text("Bezahlung\(tableName.map { " — \($0)" } ?? "")")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Bestellung #\(orderId)")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()
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

// MARK: - Order Summary Panel (links)

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
        vat7NetCents:  v7n, vat7TaxCents:  v7t,
        vat19NetCents: v19n, vat19TaxCents: v19t
    )
}

private struct OrderSummaryPanel: View {
    let order: OrderDetail
    let vat:   VatBreakdownLocal
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SummarySection("POSITIONEN")
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    ForEach(order.items) { item in
                        SummaryItemRow(item: item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                SummarySection("MWST-AUFSCHLÜSSELUNG")
                    .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    if vat.has7 {
                        VatRow(label: "7 % Netto",   value: vat.vat7NetCents)
                        VatRow(label: "7 % Steuer",  value: vat.vat7TaxCents,  dim: true)
                    }
                    if vat.has19 {
                        VatRow(label: "19 % Netto",  value: vat.vat19NetCents)
                        VatRow(label: "19 % Steuer", value: vat.vat19TaxCents, dim: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                HStack {
                    Text("Gesamtbetrag (Brutto)")
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Spacer()
                    Text(formatCents(order.totalCents))
                        .font(.jakarta(18, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 28)
            }
        }
        .background(DS.C.bg)
    }
}

private struct SummarySection: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
            .foregroundColor(DS.C.text2)
            .tracking(0.5)
    }
}

private struct SummaryItemRow: View {
    let item: OrderItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(item.quantity)×")
                .font(.jakarta(DS.T.loginBody, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)
                if !item.modifiers.isEmpty {
                    Text(item.modifiers.map { $0.name }.joined(separator: ", "))
                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .lineLimit(1)
                }
                Text("\(item.vatRate) % MwSt")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Text(formatCents(item.subtotalCents))
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

private struct VatRow: View {
    let label: String
    let value: Int
    var dim:   Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
            Spacer()
            Text(formatCents(value))
                .font(.jakarta(DS.T.loginBody, weight: .semibold))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
        }
    }
}

// MARK: - Payment Panel (rechts)

private struct PaymentPanel: View {
    @Binding var payMode:   PaymentView.PayMode
    @Binding var cashInput: String
    let totalCents: Int
    let isLoading:  Bool
    let onPay:      () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var cashFocused = false

    private var cashCents:     Int  { parseCents(cashInput) }
    private var cardCents:     Int  { max(0, totalCents - cashCents) }
    private var cashOverflow:  Bool { cashCents > totalCents }
    private var gemischtValid: Bool { cashCents > 0 && !cashOverflow }
    private var canPay:        Bool { payMode != .gemischt || gemischtValid }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Zahlungsart")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.C.sur)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight),
                alignment: .bottom
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Zahlungsart-Buttons
                    VStack(spacing: 8) {
                        PayModeButton(
                            icon:     "banknote",
                            label:    "Bar",
                            isActive: payMode == .bar,
                            onTap:    { withAnimation(.easeInOut(duration: 0.15)) { payMode = .bar } }
                        )
                        PayModeButton(
                            icon:     "creditcard",
                            label:    "Karte",
                            isActive: payMode == .karte,
                            onTap:    { withAnimation(.easeInOut(duration: 0.15)) { payMode = .karte } }
                        )
                        PayModeButton(
                            icon:     "shuffle",
                            label:    "Gemischt",
                            isActive: payMode == .gemischt,
                            onTap:    { withAnimation(.easeInOut(duration: 0.15)) { payMode = .gemischt } }
                        )
                    }

                    // Gemischt-Details
                    if payMode == .gemischt {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AUFTEILUNG")
                                .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                                .foregroundColor(DS.C.text2)
                                .tracking(0.5)

                            // Barbetrag-Eingabe
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Barbetrag")
                                    .font(.jakarta(DS.T.loginFooter, weight: .semibold))
                                    .foregroundColor(DS.C.text2)
                                NoAssistantTextField(
                                    placeholder:  "0,00 €",
                                    text:         $cashInput,
                                    keyboardType: .decimalPad,
                                    uiFont:       UIFont.systemFont(ofSize: 14),
                                    uiTextColor:  UIColor(DS.C.text),
                                    isFocused:    $cashFocused
                                )
                                .padding(.horizontal, 12)
                                .frame(height: DS.S.inputHeight)
                                .background(DS.C.bg)
                                .cornerRadius(DS.R.input)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.R.input)
                                        .strokeBorder(
                                            cashOverflow  ? Color(hex: "e74c3c") :
                                            cashFocused   ? DS.C.acc : DS.C.brd(colorScheme),
                                            lineWidth: 1
                                        )
                                )
                                .animation(.easeInOut(duration: 0.15), value: cashFocused)
                            }

                            // Kartenbetrag — auto-berechnet
                            HStack {
                                Text("Kartenbetrag")
                                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                                    .foregroundColor(DS.C.text2)
                                Spacer()
                                Text(formatCents(cardCents))
                                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                                    .foregroundColor(gemischtValid ? DS.C.text : DS.C.text2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.input)

                            if cashOverflow {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                    Text("Barbetrag übersteigt Gesamtbetrag")
                                        .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                }
                                .foregroundColor(Color(hex: "e74c3c"))
                            }
                        }
                        .padding(14)
                        .background(DS.C.sur)
                        .cornerRadius(DS.R.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.card)
                                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Zu-zahlen-Chip
                    HStack {
                        Text("Zu zahlen")
                            .font(.jakarta(DS.T.loginBody, weight: .semibold))
                            .foregroundColor(DS.C.accT)
                        Spacer()
                        Text(formatCents(totalCents))
                            .font(.jakarta(18, weight: .semibold))
                            .foregroundColor(DS.C.accT)
                            .tracking(-0.3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(DS.C.accBg)
                    .cornerRadius(DS.R.card)
                }
                .padding(14)
            }

            // Bezahlen-Button
            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                Button(action: onPay) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(payLabel)
                                    .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.S.buttonHeight)
                }
                .background(canPay ? DS.C.acc : DS.C.acc.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(!canPay || isLoading)
                .opacity(isLoading ? 0.6 : 1.0)
                .padding(14)
                .animation(.easeInOut(duration: 0.15), value: canPay)
                .buttonStyle(.plain)
            }
            .background(DS.C.sur)
        }
        .background(DS.C.bg)
    }

    private var payLabel: String {
        switch payMode {
        case .bar:      return "Bar — \(formatCents(totalCents))"
        case .karte:    return "Karte — \(formatCents(totalCents))"
        case .gemischt: return "Gemischt — \(formatCents(totalCents))"
        }
    }
}

private struct PayModeButton: View {
    let icon:     String
    let label:    String
    let isActive: Bool
    let onTap:    () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text)
                    .frame(width: 20)
                Text(label)
                    .font(.jakarta(DS.T.loginButton, weight: .semibold))
                    .foregroundColor(isActive ? .white : DS.C.text)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: DS.S.buttonHeight)
            .background(isActive ? DS.C.acc : DS.C.sur)
            .cornerRadius(DS.R.button)
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .strokeBorder(
                        isActive ? DS.C.acc : DS.C.brd(colorScheme),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bon-Zusammenfassung

private struct ReceiptSummarySheet: View {
    let result:    PaymentResult
    let tableName: String?
    let onDone:    () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Drag Indicator
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            // Success-Header
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
                    // Zahlungsmittel
                    VStack(alignment: .leading, spacing: 10) {
                        ReceiptSectionHeader("ZAHLUNG")
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
                                    Text(formatCents(p.amountCents))
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

                    // MwSt-Aufschlüsselung
                    VStack(alignment: .leading, spacing: 10) {
                        ReceiptSectionHeader("MWST-AUFSCHLÜSSELUNG")
                        VStack(spacing: 6) {
                            let has7  = result.vat7NetCents  + result.vat7TaxCents  > 0
                            let has19 = result.vat19NetCents + result.vat19TaxCents > 0
                            if has7 {
                                ReceiptVatRow(label: "7 % Netto",  value: result.vat7NetCents)
                                ReceiptVatRow(label: "7 % Steuer", value: result.vat7TaxCents, dim: true)
                            }
                            if has19 {
                                ReceiptVatRow(label: "19 % Netto",  value: result.vat19NetCents)
                                ReceiptVatRow(label: "19 % Steuer", value: result.vat19TaxCents, dim: true)
                            }
                            Divider()
                            ReceiptVatRow(label: "Gesamt (Brutto)", value: result.totalGrossCents, bold: true)
                        }
                        .padding(12)
                        .background(DS.C.sur)
                        .cornerRadius(DS.R.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.card)
                                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                        )
                    }

                    // TSE-Hinweis
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

            // Fertig-Button
            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                Button(action: onDone) {
                    Text("Fertig")
                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.S.buttonHeight)
                }
                .background(DS.C.acc)
                .cornerRadius(DS.R.button)
                .padding(14)
                .buttonStyle(.plain)
            }
            .background(DS.C.sur)
        }
        .background(DS.C.sur)
        .presentationDragIndicator(.hidden)
    }
}

private struct ReceiptSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
            .foregroundColor(DS.C.text2)
            .tracking(0.5)
    }
}

private struct ReceiptVatRow: View {
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
            Text(formatCents(value))
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.acc : (dim ? DS.C.text2 : DS.C.text))
        }
    }
}

// MARK: - Helpers

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
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
                    id: 1, productId: 1, productName: "Cappuccino",
                    productPriceCents: 350, vatRate: "19", quantity: 2,
                    subtotalCents: 700, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: [
                        OrderItemModifier(modifierOptionId: 2, name: "Hafermilch", priceDeltaCents: 50)
                    ]
                ),
                OrderItem(
                    id: 2, productId: 6, productName: "Shisha Miete",
                    productPriceCents: 1500, vatRate: "19", quantity: 1,
                    subtotalCents: 1500, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: [
                        OrderItemModifier(modifierOptionId: 4, name: "Double Apple", priceDeltaCents: 0)
                    ]
                ),
                OrderItem(
                    id: 3, productId: 8, productName: "Chips",
                    productPriceCents: 200, vatRate: "7", quantity: 1,
                    subtotalCents: 200, discountCents: 0, discountReason: nil,
                    createdAt: "", modifiers: []
                ),
            ],
            totalCents: 2400
        )
    }
}

// MARK: - Previews

#Preview("Bar — Tisch 3") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Gemischt") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    PaymentView(order: .previewSample, tableName: "Tisch 3")
        .environmentObject(OrderStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

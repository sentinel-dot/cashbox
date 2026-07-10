// ReceiptView.swift
// cashbox — Bon-Anzeige: Erfolgs-Spalte + Bon-Dokument
// Design v3: Bon-Dokument mit Beleg-Charakter (Monospace-Ziffern,
// gestrichelte Trennlinien), MwSt getrennt nach 7 % und 19 %.

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Root

struct ReceiptView: View {
    let receiptId: Int

    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var receipt:  ReceiptDetail?
    @State private var isLoading = true
    @State private var error:    AppError?
    @State private var showError = false

    private let api = APIClient.shared

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                RTopBar(receipt: receipt, onClose: { dismiss() })

                if isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if let r = receipt {
                    RContent(receipt: r, onNewOrder: { dismiss() })
                } else {
                    DSEmptyState(
                        icon: "doc.questionmark",
                        title: "Bon nicht gefunden",
                        message: "Der Bon konnte nicht geladen werden."
                    )
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .task { await loadReceipt() }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func loadReceipt() async {
        isLoading = true
        defer { isLoading = false }
        do {
            receipt = try await api.get("/receipts/\(receiptId)")
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

// MARK: - Top Bar

private struct RTopBar: View {
    let receipt:  ReceiptDetail?
    let onClose:  () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Zurück")
                        .font(DS.F.bodyMed)
                }
                .foregroundColor(DS.C.accT)
                .padding(.horizontal, 16)
                .frame(height: DS.S.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            Spacer()

            Text("Bon")
                .font(DS.F.bodyBold)
                .foregroundColor(DS.C.text)

            Spacer()

            DSPill(
                label: receipt != nil ? "Zahlung erfolgreich" : "Bon",
                fg: DS.C.successText,
                bg: DS.C.successBg
            )
            .padding(.trailing, DS.S.pagePad)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

// MARK: - Content

private struct RContent: View {
    let receipt:    ReceiptDetail
    let onNewOrder: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 28) {
                RSuccessCol(receipt: receipt, onNewOrder: onNewOrder)
                    .frame(width: 240)

                RReceiptDoc(receipt: receipt)
                    .frame(width: 400)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Success Column (links)

private struct RSuccessCol: View {
    let receipt:    ReceiptDetail
    let onNewOrder: () -> Void

    private var totalCents: Int { receipt.rawReceiptJson?.totalGrossCents ?? receipt.totalGrossCents }
    private var payMethod:  String {
        receipt.rawReceiptJson?.payments.first?.method.displayName ?? "—"
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(DS.C.successBg)
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(DS.C.successText)
            }

            VStack(spacing: 6) {
                Text("Zahlung erfolgreich")
                    .font(DS.F.heading)
                    .foregroundColor(DS.C.text)
                    .multilineTextAlignment(.center)

                MoneyText(cents: totalCents, size: 32, weight: .bold, color: DS.C.accT)

                Text("\(formatDate(receipt.createdAt)) · \(formatTime(receipt.createdAt))\n\(payMethod)")
                    .font(DS.F.caption)
                    .foregroundColor(DS.C.text2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Aktionen (PDF/Druck: Phase 5, Storno: über Bon-Liste)
            VStack(spacing: 8) {
                Button {
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .semibold))
                        Text("PDF senden")
                    }
                }
                .buttonStyle(DSSecondaryButton(height: 46))
                .disabled(true)  // Phase 5

                Button {
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "printer")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Bon drucken")
                    }
                }
                .buttonStyle(DSSecondaryButton(height: 46))
                .disabled(true)  // Phase 5
            }

            Rectangle()
                .fill(DS.C.brdAdaptive)
                .frame(height: 1)

            Button {
                onNewOrder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Neue Bestellung")
                }
            }
            .buttonStyle(DSPrimaryButton())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Receipt Document (rechts)

/// Gestrichelte Trennlinie — Beleg-Idiom
private struct RDashedLine: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundColor(DS.C.brdAdaptive)
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return p
        }
    }
}

private struct RReceiptDoc: View {
    let receipt: ReceiptDetail

    private var snap: ReceiptSnapshot? { receipt.rawReceiptJson }
    private var nettoCents:  Int {
        (snap?.vat19NetCents ?? 0) + (snap?.vat7NetCents ?? 0)
    }
    private var totalCents: Int {
        snap?.totalGrossCents ?? receipt.totalGrossCents
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Betrieb + Adresse (zentriert)
            VStack(spacing: 5) {
                Text(snap?.tenant.name ?? "cashbox")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(DS.C.text)
                if let tenant = snap?.tenant {
                    Text(tenantAddressLine(tenant))
                        .font(.system(size: 12))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            RDashedLine().padding(.horizontal, 16)

            // Meta: 2×2
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    RMetaCell(label: "Bon-Nr.", value: "#\(receipt.receiptNumber)")
                    RMetaCell(label: "Datum", value: formatDate(receipt.createdAt))
                }
                HStack(spacing: 0) {
                    RMetaCell(label: "Uhrzeit", value: formatTimeFull(receipt.createdAt))
                    RMetaCell(label: "Gerät", value: receipt.deviceName)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            RDashedLine().padding(.horizontal, 16)

            // Positionen
            if let items = snap?.items, !items.isEmpty {
                RItemRows(items: items)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                RDashedLine().padding(.horizontal, 16)
            }

            // Netto + MwSt (getrennt nach Satz)
            VStack(spacing: 5) {
                RTotalRow(label: "Netto", cents: nettoCents)
                if let s = snap, s.vat7NetCents + s.vat7TaxCents > 0 {
                    RTotalRow(label: "MwSt. 7 %", cents: s.vat7TaxCents)
                }
                if let s = snap, s.vat19NetCents + s.vat19TaxCents > 0 {
                    RTotalRow(label: "MwSt. 19 %", cents: s.vat19TaxCents)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Gesamt
            HStack {
                Text("Gesamt")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Text(euroString(totalCents))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(DS.C.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.C.sur2)

            // Zahlung
            if let payments = snap?.payments, !payments.isEmpty {
                VStack(spacing: 5) {
                    ForEach(payments.indices, id: \.self) { i in
                        let p = payments[i]
                        RTotalRow(label: p.method.displayName, cents: p.amountCents)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                RDashedLine().padding(.horizontal, 16)
            }

            // QR + TSE
            HStack(alignment: .top, spacing: 14) {
                if receipt.tsePending {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brdAdaptive, lineWidth: 1.5)
                            .frame(width: 72, height: 72)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(DS.C.brassText)
                    }
                } else if let sig = receipt.tseSignature, let qrImg = generateQR(sig) {
                    Image(uiImage: qrImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.C.brdAdaptive, lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DS.C.brdAdaptive, lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("TSE-Signatur (KassenSichV)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .padding(.bottom, 2)

                    if receipt.tsePending {
                        Text("Ausstehend — wird nachsigniert")
                            .font(.system(size: 12))
                            .foregroundColor(DS.C.brassText)
                    } else {
                        if let sn = receipt.tseSerialNumber {
                            RTseRow(key: "Seriennr.", value: String(sn.prefix(8)) + "…")
                        }
                        if let counter = receipt.tseCounter {
                            RTseRow(key: "Counter", value: "\(counter)")
                        }
                        if let start = receipt.tseTransactionStart {
                            RTseRow(key: "TX-Start", value: formatTimeFull(start))
                        }
                        if let end = receipt.tseTransactionEnd {
                            RTseRow(key: "TX-Ende", value: formatTimeFull(end))
                        }
                        if let sig = receipt.tseSignature {
                            RTseRow(key: "Signatur", value: String(sig.prefix(8)) + "…")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            RDashedLine().padding(.horizontal, 16)

            // Footer
            Text("Vielen Dank für Ihren Besuch! · \(snap?.tenant.name ?? "cashbox")")
                .font(.system(size: 12))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.card)
                .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
        )
    }

    private func tenantAddressLine(_ t: ReceiptTenantSnapshot) -> String {
        var parts = [t.address]
        if let tax = t.taxNumber { parts.append("St.-Nr.: \(tax)") }
        if let vat = t.vatId     { parts.append("USt-IdNr.: \(vat)") }
        return parts.joined(separator: " · ")
    }
}

private struct RTotalRow: View {
    let label: String
    let cents: Int
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(DS.C.text2)
            Spacer()
            Text(euroString(cents))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.C.text)
        }
    }
}

private struct RItemRows: View {
    let items: [ReceiptItemSnapshot]

    private struct Row: Identifiable {
        let id: Int
        let item: ReceiptItemSnapshot
    }

    private var rows: [Row] {
        items.enumerated().map { Row(id: $0.offset, item: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.id) { (row: Row) in
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.item.productName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Text("\(row.item.quantity) × \(euroString(row.item.productPriceCents))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(DS.C.text2)
                    }
                    Spacer()
                    Text(euroString(row.item.subtotalCents))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.C.text)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct RMetaCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.C.text2)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.C.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RTseRow: View {
    let key:   String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11))
                .foregroundColor(DS.C.text2)
                .frame(minWidth: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.C.text)
        }
    }
}

// MARK: - Helpers

private func generateQR(_ content: String) -> UIImage? {
    let context = CIContext()
    let filter  = CIFilter.qrCodeGenerator()
    filter.message = Data(content.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
    guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

private func formatDate(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    out.locale = Locale(identifier: "de_DE")
    return out.string(from: d)
}

private func formatTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateStyle = .none
    out.timeStyle = .short
    out.locale = Locale(identifier: "de_DE")
    return out.string(from: d)
}

private func formatTimeFull(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "HH:mm:ss"
    out.locale = Locale(identifier: "de_DE")
    return out.string(from: d)
}

// MARK: - Previews

#Preview("Bon") {
    ReceiptView(receiptId: 42)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    ReceiptView(receiptId: 42)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    ReceiptView(receiptId: 42)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

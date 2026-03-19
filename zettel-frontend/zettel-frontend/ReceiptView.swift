// ReceiptView.swift
// cashbox — Bon-Anzeige: Erfolgs-Spalte + Bon-Dokument

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Root

struct ReceiptView: View {
    let receiptId: Int

    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                    Spacer()
                    Text("Bon konnte nicht geladen werden.")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
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

            // "Zahlung erfolgreich" chip
            HStack(spacing: 5) {
                Circle()
                    .fill(DS.C.successText)
                    .frame(width: 6, height: 6)
                Text(receipt != nil ? "Zahlung erfolgreich" : "Bon")
                    .font(.jakarta(11, weight: .semibold))
                    .foregroundColor(DS.C.successText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.C.successBg)
            .cornerRadius(20)
            .padding(.trailing, 20)
        }
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

// MARK: - Content

private struct RContent: View {
    let receipt:    ReceiptDetail
    let onNewOrder: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 24) {
                RSuccessCol(receipt: receipt, onNewOrder: onNewOrder)
                    .frame(width: 200)

                RReceiptDoc(receipt: receipt)
                    .frame(width: 380)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Success Column (links, 200px)

private struct RSuccessCol: View {
    let receipt:    ReceiptDetail
    let onNewOrder: () -> Void

    private var totalCents: Int { receipt.rawReceiptJson?.totalGrossCents ?? receipt.totalGrossCents }
    private var payMethod:  String {
        receipt.rawReceiptJson?.payments.first?.method.displayName ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            // Success icon
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(DS.C.successBg)
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(DS.C.successText)
            }

            Text("Zahlung erfolgreich")
                .font(.jakarta(16, weight: .semibold))
                .foregroundColor(DS.C.text)
                .tracking(-0.2)
                .multilineTextAlignment(.center)

            Text(rFmt(totalCents))
                .font(.jakarta(28, weight: .semibold))
                .foregroundColor(DS.C.acc)
                .tracking(-0.5)

            Text("\(formatDate(receipt.createdAt))\n\(formatTime(receipt.createdAt)) · \(payMethod)")
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Action buttons
            VStack(spacing: 8) {
                RActionBtn(
                    icon:    "doc.text",
                    label:   "PDF senden",
                    style:   .primary,
                    enabled: false  // Phase 5
                ) {}

                RActionBtn(
                    icon:    "printer",
                    label:   "Bon drucken",
                    style:   .secondary,
                    enabled: false  // Phase 5
                ) {}

                RActionBtn(
                    icon:    "arrow.uturn.backward",
                    label:   "Stornieren",
                    style:   .ghost,
                    enabled: false  // TODO: Storno via API
                ) {}
            }

            Rectangle()
                .fill(DS.C.brdLight)
                .frame(height: 1)

            // Neuer Tisch / Bestellung
            Button(action: onNewOrder) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Neuer Tisch / Bestellung")
                        .font(.jakarta(13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .background(DS.C.acc)
            .cornerRadius(12)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum RBtnStyle { case primary, secondary, ghost }

private struct RActionBtn: View {
    let icon:    String
    let label:   String
    let style:   RBtnStyle
    let enabled: Bool
    let onTap:   () -> Void
    @Environment(\.colorScheme) private var cs

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.jakarta(12, weight: .semibold))
            }
            .foregroundColor(fgColor)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(bgColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: style == .primary ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.4)
        .disabled(!enabled)
    }

    private var fgColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return DS.C.text
        case .ghost:     return DS.C.text2
        }
    }
    private var bgColor: Color {
        switch style {
        case .primary:   return DS.C.acc
        case .secondary: return DS.C.sur
        case .ghost:     return Color.clear
        }
    }
    private var borderColor: Color {
        DS.C.brd(cs)
    }
}

// MARK: - Receipt Document (rechts, 380px)

private struct RReceiptDoc: View {
    let receipt: ReceiptDetail
    @Environment(\.colorScheme) private var cs

    private var snap: ReceiptSnapshot? { receipt.rawReceiptJson }
    private var nettoCents:  Int {
        (snap?.vat19NetCents ?? 0) + (snap?.vat7NetCents ?? 0)
    }
    private var vatCents: Int {
        (snap?.vat19TaxCents ?? 0) + (snap?.vat7TaxCents ?? 0)
    }
    private var totalCents: Int {
        snap?.totalGrossCents ?? receipt.totalGrossCents
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Betrieb + Adresse (zentriert)
            VStack(spacing: 4) {
                Text(snap?.tenant.name ?? "Kassensystem")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                if let tenant = snap?.tenant {
                    Text(tenantAddressLine(tenant))
                        .font(.system(size: 10, design: .default))
                        .foregroundColor(DS.C.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            // Meta: 2×2 grid
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    RMetaCell(label: "BON-NR.", value: "#\(receipt.receiptNumber)")
                    Rectangle().fill(DS.C.brdLight).frame(width: 1)
                    RMetaCell(label: "DATUM", value: formatDate(receipt.createdAt))
                }
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                HStack(spacing: 0) {
                    RMetaCell(label: "UHRZEIT", value: formatTimeFull(receipt.createdAt))
                    Rectangle().fill(DS.C.brdLight).frame(width: 1)
                    RMetaCell(label: "GERÄT", value: receipt.deviceName)
                }
            }

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            // Positionen
            if let items = snap?.items, !items.isEmpty {
                RItemRows(items: items, fmt: rFmt)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
            }

            // Netto + MwSt rows
            VStack(spacing: 4) {
                HStack {
                    Text("Netto")
                        .font(.system(size: 11))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(rFmt(nettoCents))
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
                HStack {
                    Text("MwSt. 19 % (auf \(rFmt(totalCents)))")
                        .font(.system(size: 11))
                        .foregroundColor(DS.C.text2)
                    Spacer()
                    Text(rFmt(vatCents))
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            // Gesamt (bg background, acc value)
            HStack {
                Text("Gesamt")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Text(rFmt(totalCents))
                    .font(.jakarta(16, weight: .semibold))
                    .foregroundColor(DS.C.acc)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DS.C.bg)

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            // Zahlung
            if let payments = snap?.payments, !payments.isEmpty {
                VStack(spacing: 3) {
                    ForEach(payments.indices, id: \.self) { i in
                        let p = payments[i]
                        HStack {
                            Text(p.method.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(DS.C.text2)
                            Spacer()
                            Text(rFmt(p.amountCents))
                                .font(.jakarta(11, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Rectangle().fill(DS.C.brdLight).frame(height: 1)
            }

            // QR + TSE
            HStack(alignment: .top, spacing: 14) {
                // QR-Code
                if receipt.tsePending {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.C.brd(cs), lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(DS.C.text2)
                    }
                } else if let sig = receipt.tseSignature, let qrImg = generateQR(sig) {
                    Image(uiImage: qrImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.C.brd(cs), lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DS.C.brd(cs), lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                }

                // TSE info
                VStack(alignment: .leading, spacing: 2) {
                    Text("TSE-SIGNATUR (KASSENSICHV)")
                        .font(.system(size: 9))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)
                        .padding(.bottom, 2)

                    if receipt.tsePending {
                        Text("Ausstehend – wird nachsigniert")
                            .font(.system(size: 9))
                            .foregroundColor(DS.C.warnText)
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

            Rectangle().fill(DS.C.brdLight).frame(height: 1)

            // Footer
            Text("Vielen Dank für Ihren Besuch! · \(snap?.tenant.name ?? "Kassensystem")")
                .font(.system(size: 10))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .background(DS.C.sur)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.C.brd(cs), lineWidth: 1)
        )
    }

    private func tenantAddressLine(_ t: ReceiptTenantSnapshot) -> String {
        var parts = [t.address]
        if let tax = t.taxNumber { parts.append("St.-Nr.: \(tax)") }
        if let vat = t.vatId     { parts.append("USt-IdNr.: \(vat)") }
        return parts.joined(separator: " · ")
    }
}

private struct RItemRows: View {
    let items: [ReceiptItemSnapshot]
    let fmt: (Int) -> String

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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.item.productName)
                            .font(.jakarta(12, weight: .semibold))
                            .foregroundColor(DS.C.text)
                        Text("\(row.item.quantity) × \(fmt(row.item.productPriceCents))")
                            .font(.system(size: 10))
                            .foregroundColor(DS.C.text2)
                    }
                    Spacer()
                    Text(fmt(row.item.subtotalCents))
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(DS.C.text)
                }
                .padding(.vertical, 5)
                if row.id < items.count - 1 {
                    Rectangle().fill(DS.C.brdLight).frame(height: 1)
                }
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
                .font(.system(size: 9))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
            Text(value)
                .font(.jakarta(11, weight: .semibold))
                .foregroundColor(DS.C.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct RTseRow: View {
    let key:   String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 9))
                .foregroundColor(DS.C.text2)
                .frame(minWidth: 55, alignment: .leading)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
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

private let _rFmt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale = Locale(identifier: "de_DE")
    return f
}()

private func rFmt(_ cents: Int) -> String {
    let val = NSNumber(value: Double(cents) / 100.0)
    return (_rFmt.string(from: val) ?? "0,00") + " €"
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

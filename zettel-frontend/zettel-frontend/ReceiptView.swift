// ReceiptView.swift
// cashbox — Bon-Anzeige: alle Pflichtfelder (KassenSichV + GoBD + §14 UStG), QR-Code

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Root

struct ReceiptView: View {
    let receiptId: Int

    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var receipt:   ReceiptDetail?
    @State private var isLoading  = true
    @State private var error:     AppError?
    @State private var showError  = false

    private let api = APIClient.shared

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ReceiptTopBar(
                    receiptNumber: receipt?.receiptNumber,
                    onClose: { dismiss() }
                )

                if isLoading {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if let r = receipt {
                    ReceiptContent(receipt: r)
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

private struct ReceiptTopBar: View {
    let receiptNumber: Int?
    let onClose: () -> Void
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
                Text(receiptNumber.map { "Bon #\($0)" } ?? "Bon")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Kassenbelegpflichtig")
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

// MARK: - Content (zweispaltig)

private struct ReceiptContent: View {
    let receipt: ReceiptDetail
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Links: Bon-Details
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let snap = receipt.rawReceiptJson {
                        TenantSection(tenant: snap.tenant)
                        Divider20()
                        ItemsSection(items: snap.items)
                        Divider20()
                        VatSection(
                            vat7Net:  snap.vat7NetCents,  vat7Tax:  snap.vat7TaxCents,
                            vat19Net: snap.vat19NetCents, vat19Tax: snap.vat19TaxCents,
                            total:    snap.totalGrossCents
                        )
                        Divider20()
                        PaymentsSection(payments: snap.payments)
                    } else {
                        // Fallback: direkt aus ReceiptDetail-Feldern
                        VatSection(
                            vat7Net:  receipt.vat7NetCents,  vat7Tax:  receipt.vat7TaxCents,
                            vat19Net: receipt.vat19NetCents, vat19Tax: receipt.vat19TaxCents,
                            total:    receipt.totalGrossCents
                        )
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(DS.C.brdLight).frame(width: 1)

            // Rechts: TSE + QR
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MetaSection(receipt: receipt)
                    TseSection(receipt: receipt)
                }
                .padding(20)
            }
            .frame(width: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.C.bg)
    }
}

// MARK: - Sections

private struct TenantSection: View {
    let tenant: ReceiptTenantSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BonSectionHeader("BETRIEB")
            Text(tenant.name)
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text(tenant.address)
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
            if let vat = tenant.vatId {
                Text("USt-IdNr.: \(vat)")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            if let tax = tenant.taxNumber {
                Text("Steuernummer: \(tax)")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
    }
}

private struct ItemsSection: View {
    let items: [ReceiptItemSnapshot]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BonSectionHeader("POSITIONEN")
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("\(item.quantity)×")
                            .font(.jakarta(DS.T.loginBody, weight: .semibold))
                            .foregroundColor(DS.C.text2)
                            .frame(width: 26, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.productName)
                                .font(.jakarta(DS.T.loginBody, weight: .semibold))
                                .foregroundColor(DS.C.text)
                            Text("\(formatCents(item.productPriceCents)) · \(item.vatRate) % MwSt")
                                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                .foregroundColor(DS.C.text2)
                            if item.discountCents > 0 {
                                Text("Rabatt: –\(formatCents(item.discountCents))\(item.discountReason.map { " (\($0))" } ?? "")")
                                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                    .foregroundColor(DS.C.acc)
                            }
                        }
                        Spacer()
                        Text(formatCents(item.subtotalCents))
                            .font(.jakarta(DS.T.loginBody, weight: .semibold))
                            .foregroundColor(DS.C.text)
                    }
                    .padding(10)
                    .background(DS.C.sur)
                    .cornerRadius(DS.R.pinRow)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.pinRow).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                }
            }
        }
    }
}

private struct VatSection: View {
    let vat7Net: Int;  let vat7Tax: Int
    let vat19Net: Int; let vat19Tax: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BonSectionHeader("MWST-AUFSCHLÜSSELUNG (§14 UStG)")
            VStack(spacing: 5) {
                if vat7Net + vat7Tax > 0 {
                    BonRow(label: "7 % Netto",   value: formatCents(vat7Net))
                    BonRow(label: "7 % MwSt",    value: formatCents(vat7Tax), dim: true)
                }
                if vat19Net + vat19Tax > 0 {
                    BonRow(label: "19 % Netto",  value: formatCents(vat19Net))
                    BonRow(label: "19 % MwSt",   value: formatCents(vat19Tax), dim: true)
                }
                Divider()
                BonRow(label: "Gesamt (Brutto)", value: formatCents(total), bold: true)
            }
        }
    }
}

private struct PaymentsSection: View {
    let payments: [ReceiptPaymentSnapshot]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BonSectionHeader("ZAHLUNG")
            ForEach(payments.indices, id: \.self) { i in
                let p = payments[i]
                BonRow(
                    label: p.method.displayName,
                    value: formatCents(p.amountCents),
                    icon:  p.method.icon
                )
            }
        }
    }
}

private struct MetaSection: View {
    let receipt: ReceiptDetail
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BonSectionHeader("BON-INFO")
            VStack(spacing: 5) {
                BonRow(label: "Bon-Nr.",   value: "#\(receipt.receiptNumber)")
                BonRow(label: "Kassensystem", value: "\(receipt.deviceName) (#\(receipt.deviceId))")
                BonRow(label: "Datum",     value: formatDate(receipt.createdAt))
                BonRow(label: "Uhrzeit",   value: formatTime(receipt.createdAt))
                if receipt.isSplitReceipt {
                    BonRow(label: "Typ", value: "Split-Bon")
                }
            }
        }
    }
}

private struct TseSection: View {
    let receipt: ReceiptDetail
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BonSectionHeader("TSE (KassenSichV)")

            if receipt.tsePending {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                    Text("TSE-Signatur ausstehend")
                        .font(.jakarta(DS.T.loginBody, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(DS.R.card)
                Text("Bon wird nach Verbindungsherstellung automatisch nachsigniert und ist bis dahin rechtlich unvollständig.")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            } else {
                VStack(spacing: 5) {
                    if let sn = receipt.tseSerialNumber {
                        BonRow(label: "Seriennummer", value: String(sn.prefix(16)) + "…")
                    }
                    if let counter = receipt.tseCounter {
                        BonRow(label: "TX-Counter", value: "\(counter)")
                    }
                    if let start = receipt.tseTransactionStart {
                        BonRow(label: "TX-Start", value: formatTime(start))
                    }
                    if let end = receipt.tseTransactionEnd {
                        BonRow(label: "TX-Ende", value: formatTime(end))
                    }
                }

                // QR-Code
                if let sig = receipt.tseSignature, let qr = generateQR(sig) {
                    VStack(spacing: 6) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160, height: 160)
                            .cornerRadius(8)
                        Text("TSE-Signatur (BSI TR-03153)")
                            .font(.jakarta(DS.T.loginFooter, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(DS.C.sur)
                    .cornerRadius(DS.R.card)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Reusable Bon-Komponenten

private struct BonSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
            .foregroundColor(DS.C.text2)
            .tracking(0.5)
    }
}

private struct BonRow: View {
    let label: String
    let value: String
    var dim:  Bool   = false
    var bold: Bool   = false
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(DS.C.text2)
            }
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(dim ? DS.C.text2 : DS.C.text)
            Spacer()
            Text(value)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? DS.C.acc : (dim ? DS.C.text2 : DS.C.text))
        }
    }
}

private struct Divider20: View {
    var body: some View {
        Rectangle().fill(DS.C.brdLight).frame(height: 1)
            .padding(.vertical, 16)
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

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
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

// MARK: - Previews

#Preview("Bon mit TSE") {
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

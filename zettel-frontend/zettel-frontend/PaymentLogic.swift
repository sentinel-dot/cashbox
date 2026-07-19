// PaymentLogic.swift
// cashbox — reine Zahlungs- und MwSt-Logik, aus PaymentView extrahiert,
// damit sie im Test-Target ohne UI prüfbar ist (REQ-GELD-006, REQ-UX-003).

import Foundation

// MARK: - MwSt-Aufschlüsselung (Formelparität mit Backend calcVat)

struct VatBreakdownLocal {
    let vat7NetCents:  Int
    let vat7TaxCents:  Int
    let vat19NetCents: Int
    let vat19TaxCents: Int
    var has7:  Bool { vat7NetCents  + vat7TaxCents  > 0 }
    var has19: Bool { vat19NetCents + vat19TaxCents > 0 }
}

func computeVat(_ items: [OrderItem]) -> VatBreakdownLocal {
    var v7n = 0, v7t = 0, v19n = 0, v19t = 0
    for item in items {
        let gross = item.subtotalCents
        let is7   = item.vatRate == "7"
        // Backend-Formel: net = round(gross × 100 / 107|119), tax = gross − net
        let net   = Int((Double(gross * 100) / Double(is7 ? 107 : 119)).rounded())
        let tax   = gross - net
        if is7 { v7n += net; v7t += tax } else { v19n += net; v19t += tax }
    }
    return VatBreakdownLocal(
        vat7NetCents: v7n, vat7TaxCents: v7t,
        vat19NetCents: v19n, vat19TaxCents: v19t
    )
}

// MARK: - Zahlungszeilen bauen

/// barRaw ist die Cent-Ziffernfolge vom Numpad ("5000" = 50,00 €).
/// Invariante: Summe der Zahlungen == totalCents (Backend lehnt alles andere mit 422 ab).
/// Gemischt mit bar > total: Überzahlung ist Rückgeld — gebucht wird bar = total.
func buildPayments(mode: PaymentView.PayMode, barRaw: String, totalCents: Int) -> [PaymentItem] {
    switch mode {
    case .bar:
        return [PaymentItem(method: .cash, amountCents: totalCents)]
    case .karte:
        return [PaymentItem(method: .card, amountCents: totalCents)]
    case .gemischt:
        let barC  = min(Int(barRaw) ?? 0, totalCents)
        let cardC = totalCents - barC
        var out: [PaymentItem] = []
        if barC  > 0 { out.append(PaymentItem(method: .cash, amountCents: barC)) }
        if cardC > 0 { out.append(PaymentItem(method: .card, amountCents: cardC)) }
        return out
    }
}

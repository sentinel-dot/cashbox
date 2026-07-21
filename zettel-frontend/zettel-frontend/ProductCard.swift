// ProductCard.swift
// cashbox — die Kassenkachel: Produktname, Kategorie, Preis, Optionen-Badge.
// Wird von OrderView (Kasse) UND SortimentView (echte Vorschau) verwendet —
// dieselbe Komponente garantiert, dass die Sortiment-Vorschau der Kasse entspricht.

import SwiftUI

struct ProductCard: View {
    let product: Product
    var dimmed:  Bool = false
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

                    if !product.isActive {
                        DSPill(label: "Inaktiv", fg: DS.C.text2, bg: DS.C.sur2)
                    } else if product.hasRequiredModifiers {
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
            .opacity(dimmed ? 0.55 : 1)
        }
        .buttonStyle(ProductCardPressStyle())
    }
}

/// Press-Feedback: kurzes Zusammendrücken + Abdunkeln
struct ProductCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

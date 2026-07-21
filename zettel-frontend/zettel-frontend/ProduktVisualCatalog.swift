// ProduktVisualCatalog.swift — S17B: der V1-Katalog der 39 semantischen
// visual_keys (docs/s17-sortiment-starterpakete.md §6). Die DB/API kennt nur
// den semantischen Schlüssel — das Mapping auf SF Symbols/Bundle-Assets lebt
// ausschließlich hier und kann später verbessert werden, ohne Daten zu migrieren.
//
// Fallback-Kette (§6.1): key == nil → nil (hochwertige Textkachel, kein Bild);
// unbekannter key (neuere API-Version) → generic; Bundle-Asset fehlt zur
// Laufzeit → generic. Nichts davon darf Decoding oder Kasse brechen.

import SwiftUI

enum ProductVisual {
    case symbol(String)       // SF Symbol
    case asset(String)        // Bundle-Asset (Template-Rendering)
}

enum ProduktVisualCatalog {

    /// (Renderer, lokalisierte Bezeichnung für Picker + VoiceOver)
    static let catalog: [String: (visual: ProductVisual, label: String)] = [
        "generic":           (.symbol("square.grid.2x2.fill"),                "Allgemein"),
        "shisha":            (.asset("product.shisha"),                      "Shisha"),
        "shisha_refill":     (.asset("product.shisha.refill"),               "Kopfwechsel"),
        "charcoal":          (.symbol("flame.fill"),                          "Kohle"),
        "tobacco":           (.symbol("leaf.fill"),                           "Tabak"),
        "smoking_accessory": (.symbol("wrench.and.screwdriver.fill"),         "Zubehör"),
        "espresso":          (.symbol("cup.and.saucer.fill"),                 "Espresso"),
        "coffee":            (.symbol("cup.and.saucer.fill"),                 "Kaffee"),
        "milk_coffee":       (.symbol("cup.and.saucer.fill"),                 "Milchkaffee"),
        "tea":               (.symbol("mug.fill"),                            "Tee"),
        "hot_chocolate":     (.symbol("mug.fill"),                            "Heiße Schokolade"),
        "water":             (.symbol("waterbottle.fill"),                    "Wasser"),
        "soft_drink":        (.symbol("takeoutbag.and.cup.and.straw.fill"),   "Limonade"),
        "spritzer":          (.symbol("bubbles.and.sparkles.fill"),           "Schorle"),
        "energy_drink":      (.symbol("bolt.fill"),                           "Energydrink"),
        "juice":             (.symbol("drop.fill"),                           "Saft"),
        "beer":              (.symbol("mug.fill"),                            "Bier"),
        "wine":              (.symbol("wineglass.fill"),                      "Wein"),
        "breakfast":         (.symbol("sun.horizon.fill"),                    "Frühstück"),
        "egg_dish":          (.symbol("frying.pan.fill"),                     "Eierspeise"),
        "soup":              (.symbol("takeoutbag.and.cup.and.straw.fill"),   "Suppe"),
        "sandwich":          (.symbol("fork.knife"),                          "Sandwich"),
        "croissant":         (.asset("product.croissant"),                    "Croissant"),
        "pretzel":           (.asset("product.pretzel"),                      "Brezel"),
        "cake":              (.symbol("birthday.cake.fill"),                  "Kuchen"),
        "nachos":            (.symbol("fork.knife"),                          "Nachos"),
        "chips":             (.symbol("takeoutbag.and.cup.and.straw.fill"),   "Chips"),
        "nuts":              (.symbol("leaf.circle.fill"),                    "Nüsse"),
        "fruit":             (.symbol("leaf.fill"),                           "Obst"),
        "chocolate":         (.symbol("square.grid.3x3.fill"),                "Schokolade"),
        "gummy_candy":       (.symbol("circle.hexagongrid.fill"),             "Fruchtgummi"),
        "cookies":           (.symbol("circle.grid.2x2.fill"),                "Kekse"),
        "ice_cream":         (.symbol("snowflake"),                           "Eis"),
        "instant_meal":      (.symbol("takeoutbag.and.cup.and.straw.fill"),   "Instantgericht"),
        "cigarettes":        (.symbol("shippingbox.fill"),                    "Zigaretten"),
        "lighter":           (.symbol("flame.fill"),                          "Feuerzeug"),
        "tissues":           (.symbol("shippingbox.fill"),                    "Taschentücher"),
        "battery":           (.symbol("battery.100percent"),                  "Batterien"),
        "cable":             (.symbol("cable.connector"),                     "Ladekabel"),
    ]

    /// Alle Keys in kuratierter Reihenfolge (für den Picker) — deterministisch.
    static let orderedKeys: [String] = [
        "shisha", "shisha_refill", "charcoal", "tobacco", "smoking_accessory",
        "espresso", "coffee", "milk_coffee", "tea", "hot_chocolate",
        "water", "soft_drink", "spritzer", "energy_drink", "juice",
        "beer", "wine",
        "breakfast", "egg_dish", "soup", "sandwich",
        "croissant", "pretzel", "cake",
        "nachos", "chips", "nuts", "fruit",
        "chocolate", "gummy_candy", "cookies", "ice_cream", "instant_meal",
        "cigarettes", "lighter", "tissues", "battery", "cable",
        "generic",
    ]

    /// nil → nil (Textkachel); unbekannt → generic; Asset fehlt → generic.
    static func visual(for key: String?) -> ProductVisual? {
        guard let key else { return nil }
        let entry = catalog[key]?.visual ?? catalog["generic"]!.visual
        if case .asset(let name) = entry, UIImage(named: name) == nil {
            return catalog["generic"]!.visual
        }
        return entry
    }

    /// Lokalisierte Bezeichnung — der technische Key wird nie vorgelesen (§6.5).
    static func label(for key: String?) -> String {
        guard let key else { return "Ohne Symbol" }
        return catalog[key]?.label ?? catalog["generic"]!.label
    }
}

/// Kleines Renderer-View: Template-Rendering, Kategorie-Farbe als Tint,
/// dekorativ (VoiceOver blendet es aus — Name + Preis sind das Label).
struct ProductVisualView: View {
    let visual: ProductVisual
    var size:   CGFloat = 22
    var tint:   Color   = DS.C.text2

    var body: some View {
        Group {
            switch visual {
            case .symbol(let name):
                Image(systemName: name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .foregroundColor(tint)
        .accessibilityHidden(true)
    }
}

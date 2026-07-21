// VisualSuggestion.swift — S17B: Namensheuristik für den Visual-Picker (§6.4).
// NUR eine Vorbelegung des optionalen Pickers — niemals Steuerlogik, niemals
// automatisches Überschreiben einer Nutzerwahl. Kein Treffer ⇒ nil (nie
// `generic` in die DB schreiben).
//
// Regeln: Ganze Wörter/Phrasen nach Normalisierung (Kleinschreibung,
// Diakritika-Faltung, ß→ss, Mengenangaben wie „0,33 l" / „200 g" entfernt).
// Die spezifischste Regel gewinnt (Reihenfolge der Tabelle); Kategorie ist nur
// ein sekundäres Signal, nie der MwSt.-Satz.

import Foundation

func suggestedVisualKey(forName name: String, categoryName: String? = nil) -> String? {
    let words = visualSuggestionNormalize(name)
    if let hit = matchVisualRules(words) { return hit }
    if let cat = categoryName {
        return matchVisualRules(visualSuggestionNormalize(cat))
    }
    return nil
}

// ── Normalisierung ───────────────────────────────────────────────────────────

func visualSuggestionNormalize(_ raw: String) -> [String] {
    var s = raw.lowercased()
        .replacingOccurrences(of: "ß", with: "ss")
        .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))

    // Mengenangaben raus: "0,33 l", "0.5l", "500 ml", "200 g", "4er", "1,0 l"
    s = s.replacingOccurrences(
        of: #"\d+([.,]\d+)?\s*(l|ml|cl|g|kg|er)\b"#,
        with: " ", options: .regularExpression
    )
    // Übrige Zahlen und Satzzeichen zu Trennern
    s = s.replacingOccurrences(of: #"[\d,.;:()\-–/]+"#, with: " ", options: .regularExpression)

    return s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
}

// ── Regeltabelle (spezifischste zuerst) ──────────────────────────────────────

private let visualRules: [(phrases: [String], key: String)] = [
    // Mehrwort-Phrasen und spezifische Komposita zuerst
    (["latte macchiato", "cappuccino", "milchkaffee", "flat white"], "milk_coffee"),
    (["heisse schokolade", "kakao", "hot chocolate"],                "hot_chocolate"),
    (["eis am stiel", "eiscreme", "speiseeis"],                      "ice_cream"),
    (["cola ohne zucker", "cola"],                                   "soft_drink"),
    (["kopfwechsel"],                                                "shisha_refill"),
    (["shisha", "wasserpfeife", "hookah"],                           "shisha"),
    (["kohle"],                                                      "charcoal"),
    (["feinschnitttabak", "wasserpfeifentabak", "tabak"],            "tobacco"),
    (["zigaretten", "zigarette"],                                    "cigarettes"),
    (["espresso", "doppio"],                                         "espresso"),
    (["cafe creme", "americano", "filterkaffee", "kaffee"],          "coffee"),
    (["minztee", "tee", "chai"],                                     "tea"),
    (["wasser"],                                                     "water"),
    (["orangenlimonade", "limonade", "limo", "spezi", "eistee"],     "soft_drink"),
    (["apfelschorle", "schorle"],                                    "spritzer"),
    (["energydrink", "energy drink", "energy"],                      "energy_drink"),
    (["orangensaft", "apfelsaft", "saft"],                           "juice"),
    (["pils", "lager", "radler", "helles", "weizen", "bier"],        "beer"),
    (["rotwein", "weisswein", "wein", "sekt", "prosecco"],           "wine"),
    (["fruhstuck"],                                                  "breakfast"),
    (["ruhrei", "spiegelei", "omelett"],                             "egg_dish"),
    (["tagessuppe", "suppe"],                                        "soup"),
    (["belegtes brotchen", "brotchen", "sandwich", "panini"],        "sandwich"),
    (["schokocroissant", "croissant"],                               "croissant"),
    (["butterbrezel", "brezel", "brezn"],                            "pretzel"),
    (["kuchen", "torte", "muffin"],                                  "cake"),
    (["nachos"],                                                     "nachos"),
    (["kartoffelchips", "chips"],                                    "chips"),
    (["erdnusse", "nusse", "nuss", "mandeln"],                       "nuts"),
    (["obstteller", "obst", "fruchte"],                              "fruit"),
    (["schokoriegel", "schokolade", "riegel"],                       "chocolate"),
    (["fruchtgummi", "kaugummi", "gummibarchen"],                    "gummy_candy"),
    (["kekse", "keks", "cookies"],                                   "cookies"),
    (["instantnudeln", "nudeln", "ramen"],                           "instant_meal"),
    (["feuerzeug"],                                                  "lighter"),
    (["taschentucher"],                                              "tissues"),
    (["batterien", "batterie"],                                      "battery"),
    (["ladekabel", "kabel"],                                         "cable"),
]

private func matchVisualRules(_ words: [String]) -> String? {
    guard !words.isEmpty else { return nil }
    for rule in visualRules {
        for phrase in rule.phrases {
            let phraseWords = phrase.split(separator: " ").map(String.init)
            if containsWordSequence(words, phraseWords) {
                return rule.key
            }
        }
    }
    return nil
}

/// Ganze-Wort-Sequenz: „tee" trifft das Wort „Tee", aber nie „Teekanne".
private func containsWordSequence(_ words: [String], _ phrase: [String]) -> Bool {
    guard !phrase.isEmpty, words.count >= phrase.count else { return false }
    for start in 0...(words.count - phrase.count) {
        var all = true
        for (offset, p) in phrase.enumerated() where words[start + offset] != p {
            all = false; break
        }
        if all { return true }
    }
    return false
}

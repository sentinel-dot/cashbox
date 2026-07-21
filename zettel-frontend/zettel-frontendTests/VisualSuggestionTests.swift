// VisualSuggestionTests.swift — TC-IOS / REQ-PRESET: Namensheuristik (§6.4).
// Alle V1-Presetnamen exakt + Negativfälle (leer, Emoji, nur Menge, unbekannt,
// sehr lang, Groß-/Kleinschreibung, Umlaute, ähnlich geschriebene Nicht-Treffer).

import XCTest
@testable import zettel_frontend

final class VisualSuggestionTests: XCTestCase {

    // ── Alle V1-Presetnamen → erwarteter Key ──

    private let presetExpectations: [(name: String, expected: String)] = [
        // shisha_bar@1
        ("Shisha Klassik", "shisha"), ("Shisha Premium", "shisha"),
        ("Shisha Fruchtkopf", "shisha"), ("Kopfwechsel", "shisha_refill"),
        ("Kohle extra", "charcoal"),
        ("Wasser still", "water"), ("Wasser sprudel", "water"),
        ("Cola", "soft_drink"), ("Cola ohne Zucker", "soft_drink"),
        ("Orangenlimonade", "soft_drink"), ("Apfelschorle", "spritzer"),
        ("Energydrink", "energy_drink"),
        ("Schwarzer Tee", "tea"), ("Frischer Minztee", "tea"),
        ("Espresso", "espresso"), ("Café Crème", "coffee"),
        ("Latte Macchiato", "milk_coffee"),
        ("Nachos mit Dip", "nachos"), ("Kartoffelchips", "chips"),
        ("Salzige Nüsse", "nuts"), ("Obstteller", "fruit"),
        // cafe@1 (zusätzliche Namen)
        ("Espresso doppio", "espresso"), ("Americano", "coffee"),
        ("Cappuccino", "milk_coffee"), ("Milchkaffee", "milk_coffee"),
        ("Heiße Schokolade", "hot_chocolate"),
        ("Tee", "tea"), ("Orangensaft", "juice"),
        ("Croissant", "croissant"), ("Schokocroissant", "croissant"),
        ("Butterbrezel", "pretzel"),
        ("Belegtes Brötchen Käse", "sandwich"), ("Belegtes Brötchen Schinken", "sandwich"),
        ("Kuchen, Stück", "cake"),
        ("Frühstück klein", "breakfast"), ("Frühstück groß", "breakfast"),
        ("Rührei", "egg_dish"), ("Tagessuppe", "soup"),
        // spaeti@1 (mit Gebinde-Angaben)
        ("Wasser still, PET 0,5 l", "water"), ("Wasser sprudel, PET 0,5 l", "water"),
        ("Cola, Dose 0,33 l", "soft_drink"), ("Cola ohne Zucker, Dose 0,33 l", "soft_drink"),
        ("Orangenlimonade, Dose 0,33 l", "soft_drink"),
        ("Apfelschorle, PET 0,5 l", "spritzer"), ("Energydrink, Dose 0,25 l", "energy_drink"),
        ("Orangensaft, Karton 1,0 l", "juice"),
        ("Pils, Dose 0,5 l", "beer"), ("Lager, Dose 0,5 l", "beer"),
        ("Radler, Dose 0,5 l", "beer"), ("Bier alkoholfrei, Dose 0,5 l", "beer"),
        ("Rotwein, Flasche 0,75 l", "wine"), ("Weißwein, Flasche 0,75 l", "wine"),
        ("Kartoffelchips, 150 g", "chips"), ("Salzige Erdnüsse, 200 g", "nuts"),
        ("Schokoriegel", "chocolate"), ("Fruchtgummi, 200 g", "gummy_candy"),
        ("Kekse, 200 g", "cookies"), ("Kaugummi", "gummy_candy"),
        ("Eis am Stiel", "ice_cream"), ("Instantnudeln, Becher", "instant_meal"),
        ("Feuerzeug", "lighter"), ("Taschentücher", "tissues"),
        ("Batterien AA, 4er", "battery"), ("Batterien AAA, 4er", "battery"),
        ("Ladekabel USB-C", "cable"),
        ("Zigaretten (Vorlage)", "cigarettes"),
        ("Feinschnitttabak (Vorlage)", "tobacco"), ("Wasserpfeifentabak (Vorlage)", "tobacco"),
    ]

    func testAlleV1PresetnamenTreffen() {
        for (name, expected) in presetExpectations {
            XCTAssertEqual(
                suggestedVisualKey(forName: name), expected,
                "'\(name)' sollte '\(expected)' vorschlagen"
            )
        }
    }

    // ── Spezifischste Regel gewinnt (§6.4 Punkt 3) ──

    func testSpezifischereRegelGewinnt() {
        XCTAssertEqual(suggestedVisualKey(forName: "Latte Macchiato"), "milk_coffee")   // nicht coffee
        XCTAssertEqual(suggestedVisualKey(forName: "Milchkaffee"), "milk_coffee")       // nicht kaffee
        XCTAssertEqual(suggestedVisualKey(forName: "Heiße Schokolade"), "hot_chocolate") // nicht chocolate
        XCTAssertEqual(suggestedVisualKey(forName: "Schokocroissant"), "croissant")      // nicht chocolate
    }

    // ── Kategorie als sekundäres Signal ──

    func testKategorieAlsSekundaeresSignal() {
        XCTAssertEqual(suggestedVisualKey(forName: "Hausmischung", categoryName: "Shisha"), "shisha")
        XCTAssertNil(suggestedVisualKey(forName: "Hausmischung", categoryName: "Spezialitäten"))
        // Name gewinnt vor Kategorie
        XCTAssertEqual(suggestedVisualKey(forName: "Cola", categoryName: "Shisha"), "soft_drink")
    }

    // ── Negativfälle: nil, nie generic ──

    func testNegativfaelle_liefernNil() {
        XCTAssertNil(suggestedVisualKey(forName: ""))
        XCTAssertNil(suggestedVisualKey(forName: "   "))
        XCTAssertNil(suggestedVisualKey(forName: "🔥🔥🔥"))
        XCTAssertNil(suggestedVisualKey(forName: "0,5 l"))              // nur Mengenangabe
        XCTAssertNil(suggestedVisualKey(forName: "Xyzzy Plugh"))        // unbekannt
        XCTAssertNil(suggestedVisualKey(forName: "Special of the day")) // fremde Sprache
        XCTAssertNil(suggestedVisualKey(forName: String(repeating: "Sehr langer Produktname ", count: 40)))
    }

    func testGanzeWoerter_keineTeilstringTreffer() {
        // „tee" darf nicht in anderen Wörtern treffen (§6.4 Punkt 2)
        XCTAssertNil(suggestedVisualKey(forName: "Teekanne"))
        XCTAssertNil(suggestedVisualKey(forName: "Nussecke"))
        XCTAssertNil(suggestedVisualKey(forName: "Colakracher"))
        XCTAssertNil(suggestedVisualKey(forName: "Weinberg-Tour"))
    }

    func testGrossKleinschreibungUndUmlaute() {
        XCTAssertEqual(suggestedVisualKey(forName: "TEE"), "tea")
        XCTAssertEqual(suggestedVisualKey(forName: "espresso"), "espresso")
        XCTAssertEqual(suggestedVisualKey(forName: "SALZIGE NÜSSE"), "nuts")
        XCTAssertEqual(suggestedVisualKey(forName: "Café Crème"), "coffee")   // Diakritika gefaltet
    }

    func testHeuristikSchlaegtNieGenericVor() {
        for (name, _) in presetExpectations {
            XCTAssertNotEqual(suggestedVisualKey(forName: name), "generic")
        }
        XCTAssertNil(suggestedVisualKey(forName: "Unbekanntes Produkt"))   // nil, nicht generic
    }
}

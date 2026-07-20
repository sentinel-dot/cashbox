# S17 Sortiment: Starter-Pakete, MwSt.-Vorschläge und Visuals V1

**Status:** verbindliche Produktspezifikation für die Umsetzung von S17A/S17B

**Fachlicher Rechtsstand:** 20.07.2026, Deutschland

**Preset-Datenstand:** Version 1

**Zielgruppe:** Betreiber/Hauptnutzer auf einem Landscape-iPad

**Verwandte Quellen:** `ROADMAP.md` S17A/S17B, `OFFEN.md` UX-S1 bis UX-S5, `DESIGN.md`

Dieses Dokument friert die fachlichen Entscheidungen ein, die vor der Umsetzung von S17B noch offen
waren: die exakten Starter-Produkte, die je Produkt vorgeschlagenen Umsatzsteuersätze und den
kuratierten `visual_key`-Katalog. Es ist zugleich die Abarbeitungs- und Abnahmegrundlage.

> Die Umsatzsteuersätze sind Produktvorschläge, keine individuelle Steuerberatung. Der Import bleibt
> gesperrt, bis ein Owner oder Manager alle vorgeschlagenen Sätze sichtbar bestätigt hat. Vor dem
> öffentlichen Go-live müssen Steuerberater und Pilotbetrieb die betriebsspezifische Zuordnung
> schriftlich freigeben. Bei einer Rechtsänderung ist eine neue `tax_basis_version` erforderlich.

## 1. Festgelegte Produktentscheidungen

### 1.1 Presets

| Anzeigename | `preset_id` | Version | Kategorien | Direkt nutzbare Produkte | Sonderzeilen |
|---|---|---:|---:|---:|---:|
| Shisha-Bar | `shisha_bar` | 1 | 4 | 21 | 0 |
| Café | `cafe` | 1 | 4 | 25 | 0 |
| Späti | `spaeti` | 1 | 5 | 27 | 3 Tabakvorlagen |
| Leer starten | `empty` | 1 | 0 | 0 | 0 |

Maschinen-IDs sind ASCII, kleingeschrieben und unveränderlich. Anzeigenamen dürfen später lokalisiert
werden. Jede fachliche Änderung an Produktmenge, MwSt.-Vorschlag, Kategorie oder Importverhalten erhöht
die Preset-Version. Eine reine Textkorrektur ohne geänderte Importdaten benötigt keine neue Version.

### 1.2 Keine Produktionspreise im Preset

Alle normalen Produkte werden mit `price_cents: null` ausgeliefert. Im Wizard ist der Preis ein
Pflichtfeld und wird ausschließlich als Integer-Cent an das Backend gesendet.

Das ist bewusst so entschieden:

- Preise unterscheiden sich stark nach Standort, Gebinde, Einkauf und Betriebskonzept.
- Ein scheinbar hilfreicher Musterpreis kann unbemerkt als echter Verkaufspreis übernommen werden.
- Tabakprodukte müssen mit dem tatsächlich auf der Packung beziehungsweise dem Steuerzeichen
  ausgewiesenen Kleinverkaufspreis angelegt werden.
- Der kompakte Preise-Schritt muss Tastatur-/Ziffernblock-fokussiert sein und 15 Produkte in wenigen
  Minuten erfassbar machen; `0,00 €` ist kein zulässiger Platzhalter für ausgewählte Produkte.

Der vorhandene Development-Seed bleibt Testdatenquelle und darf nicht als Preset oder Preisquelle
wiederverwendet werden.

### 1.3 Namen und Marken

- Starter-Produkte sind markenfrei. Begriffe wie „Cola“ oder „Energydrink“ bezeichnen eine Produktart,
  keine konkrete Marke.
- Varianten, Gebinde oder Stückzahlen stehen im Namen, wenn sie Preis, Pfand oder Kassenwahl verändern.
- Geschmacksrichtungen einer Shisha sind keine separaten Starter-Produkte. Sie gehören später in eine
  Modifier-Gruppe; dadurch bleibt das Kassenraster stabil.
- Der Betreiber darf Namen im Wizard ändern. `item_key`, Preset-Herkunft und Idempotenz bleiben davon
  unberührt.

## 2. MwSt.-Leitplanken und Bestätigungsmodell

### 2.1 Rechtsgrundlage der Vorschläge

Für Umsätze ab 01.01.2026 gelten in dieser Spezifikation folgende Leitplanken:

- Der Regelsteuersatz beträgt 19 Prozent.
- Restaurant- und Verpflegungsdienstleistungen mit Speisen unterliegen 7 Prozent; Getränke sind davon
  ausdrücklich ausgenommen.
- Viele gelieferte Lebensmittel sind nach Anlage 2 UStG begünstigt, darunter unter anderem Backwaren,
  Zuckerwaren, Schokolade und verschiedene Lebensmittelzubereitungen.
- Milchmischgetränke können bei einer Lieferung begünstigt sein, wenn der Milch-/Milcherzeugnisanteil
  mindestens 75 Prozent des Fertigerzeugnisses beträgt. Das lässt sich aus einem Produktnamen wie
  „Latte Macchiato“ nicht belastbar ableiten.

Maßgebliche Primärquellen:

- [§ 12 UStG – Steuersätze](https://www.gesetze-im-internet.de/ustg_1980/__12.html)
- [Anlage 2 UStG – begünstigte Gegenstände](https://www.gesetze-im-internet.de/ustg_1980/anlage_2.html)
- [BMF: steuerliche Änderungen 2026](https://www.bundesfinanzministerium.de/Content/DE/Standardartikel/Themen/Steuern/das-aendert-sich-2026.html)
- [BMF-Schreiben vom 22.12.2025 zu Verpflegungsdienstleistungen](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/Umsatzsteuer-Anwendungserlass/2025-12-22-verpflegungsdienstleistungen.pdf?__blob=publicationFile)

### 2.2 `tax_basis_version`

Alle V1-Vorschläge tragen serverseitig:

```text
tax_basis_version = de-ust-2026-01
```

Diese Version bedeutet ausschließlich: deutsche 7-/19-Prozent-Systematik mit Rechtsstand dieses
Dokuments. Sie ist keine Garantie für die individuelle steuerliche Behandlung.

### 2.3 Prüfklassen

| Klasse | Bedeutung | Verhalten im Wizard |
|---|---|---|
| `standard_19` | Getränk, Tabak, Zubehör oder sonstige Ware/Leistung mit 19-%-Vorschlag | Satz anzeigen; Gesamtbestätigung erforderlich |
| `food_7_2026` | Speise beziehungsweise typisches begünstigtes Lebensmittel mit 7-%-Vorschlag | Satz anzeigen; Gesamtbestätigung erforderlich |
| `recipe_review` | Der Außer-Haus-Satz hängt von Rezeptur/Zusammensetzung ab | Zeile amber markieren; Einzelbestätigung erforderlich |
| `printed_price_review` | Preisgebundene Tabakware | Name, Packungsangabe und Preis müssen einzeln bestätigt werden |

Auch grüne Standardzeilen werden niemals still übernommen. `recipe_review` und
`printed_price_review` dürfen nicht über eine globale „Alles bestätigen“-Aktion erledigt werden.

### 2.4 Inhouse/Außer-Haus während der aktuellen Phase

Das Datenmodell speichert bereits `vat_rate_inhouse` und `vat_rate_takeaway`. Die aktive Kassenlogik
verwendet derzeit jedoch nur den Inhouse-Satz; ein Außer-Haus-Umschalter bleibt gemäß `CLAUDE.md` bis zur
Freigabe von Phase 4 deaktiviert.

Trotzdem werden in S17B beide Werte bewusst erfasst:

- Speisen: Vorschlag `7 / 7`.
- Eindeutige Getränke: Vorschlag `19 / 19`.
- Milchhaltige Heißgetränke: Vorschlag `19 / 19`, aber `recipe_review` für `takeaway`; bei nachgewiesenem
  Milchanteil von mindestens 75 Prozent kann die bestätigte Zuordnung abweichen.
- Nicht-Lebensmittel, Shisha-Leistungen und Tabak: Vorschlag `19 / 19`.

Eine spätere Aktivierung der Außer-Haus-Kasse braucht weiterhin das separate Steuerberater-Gate aus
`CLAUDE.md`; S17B nimmt dieses Gate nicht vorweg.

## 3. Preset `shisha_bar@1`

### 3.1 Kategorien

| Reihenfolge | `category_key` | Anzeigename | Farbrolle |
|---:|---|---|---|
| 10 | `shisha` | Shisha | `plum` |
| 20 | `cold_drinks` | Kalte Getränke | `blue` |
| 30 | `hot_drinks` | Heißgetränke | `amber` |
| 40 | `snacks` | Snacks | `green` |

Die Farbrolle ist ein dezenter Wiedererkennungshinweis, keine Zustandsfarbe. Text und Produktname
bleiben immer sichtbar; die Kasse darf nicht von Farberkennung abhängen.

### 3.2 Produkte

`Preis` ist im Produktionspreset immer leer und im Wizard verpflichtend.

| Sort | `item_key` | Produktname | Kategorie | `visual_key` | Inhouse | Takeaway | Prüfklasse |
|---:|---|---|---|---|---:|---:|---|
| 10 | `shisha_classic` | Shisha Klassik | Shisha | `shisha` | 19 | 19 | `standard_19` |
| 20 | `shisha_premium` | Shisha Premium | Shisha | `shisha` | 19 | 19 | `standard_19` |
| 30 | `shisha_fruit_bowl` | Shisha Fruchtkopf | Shisha | `shisha` | 19 | 19 | `standard_19` |
| 40 | `shisha_head_change` | Kopfwechsel | Shisha | `shisha_refill` | 19 | 19 | `standard_19` |
| 50 | `shisha_extra_charcoal` | Kohle extra | Shisha | `charcoal` | 19 | 19 | `standard_19` |
| 10 | `water_still` | Wasser still | Kalte Getränke | `water` | 19 | 19 | `standard_19` |
| 20 | `water_sparkling` | Wasser sprudel | Kalte Getränke | `water` | 19 | 19 | `standard_19` |
| 30 | `cola` | Cola | Kalte Getränke | `soft_drink` | 19 | 19 | `standard_19` |
| 40 | `cola_zero` | Cola ohne Zucker | Kalte Getränke | `soft_drink` | 19 | 19 | `standard_19` |
| 50 | `orange_soda` | Orangenlimonade | Kalte Getränke | `soft_drink` | 19 | 19 | `standard_19` |
| 60 | `apple_spritzer` | Apfelschorle | Kalte Getränke | `spritzer` | 19 | 19 | `standard_19` |
| 70 | `energy_drink` | Energydrink | Kalte Getränke | `energy_drink` | 19 | 19 | `standard_19` |
| 10 | `black_tea` | Schwarzer Tee | Heißgetränke | `tea` | 19 | 19 | `standard_19` |
| 20 | `fresh_mint_tea` | Frischer Minztee | Heißgetränke | `tea` | 19 | 19 | `standard_19` |
| 30 | `espresso` | Espresso | Heißgetränke | `espresso` | 19 | 19 | `standard_19` |
| 40 | `cafe_creme` | Café Crème | Heißgetränke | `coffee` | 19 | 19 | `standard_19` |
| 50 | `latte_macchiato` | Latte Macchiato | Heißgetränke | `milk_coffee` | 19 | 19 | `recipe_review` |
| 10 | `nachos_dip` | Nachos mit Dip | Snacks | `nachos` | 7 | 7 | `food_7_2026` |
| 20 | `potato_chips` | Kartoffelchips | Snacks | `chips` | 7 | 7 | `food_7_2026` |
| 30 | `salted_nuts` | Salzige Nüsse | Snacks | `nuts` | 7 | 7 | `food_7_2026` |
| 40 | `fruit_plate` | Obstteller | Snacks | `fruit` | 7 | 7 | `food_7_2026` |

### 3.3 Bewusste Abgrenzungen

- Keine Marken oder Tabaksorten als Kassenprodukte.
- Keine Pflicht-Modifier in S17B. Nach dem Import darf ein separater Schritt „Geschmacksrichtungen
  einrichten“ anbieten, aber das Preset ist auch ohne ihn vollständig verkaufsfähig.
- „Shisha Klassik“ bezeichnet die bewirtete Leistung, nicht den Verkauf einer verschlossenen
  Tabakpackung. Für verschlossene Wasserpfeifentabak-Packungen gelten die Tabakregeln aus Abschnitt 6.
- Getränke dieses Gastro-Presets sind Vor-Ort-Getränke. Ein gegebenenfalls vom Gast erhobenes
  Flaschenpfand darf nicht in den Produktpreis hineingerechnet werden.

## 4. Preset `cafe@1`

### 4.1 Kategorien

| Reihenfolge | `category_key` | Anzeigename | Farbrolle |
|---:|---|---|---|
| 10 | `coffee` | Kaffee | `brown` |
| 20 | `tea_cold_drinks` | Tee & Kaltgetränke | `blue` |
| 30 | `bakery` | Backwaren | `orange` |
| 40 | `meals` | Frühstück & Speisen | `green` |

### 4.2 Produkte

| Sort | `item_key` | Produktname | Kategorie | `visual_key` | Inhouse | Takeaway | Prüfklasse |
|---:|---|---|---|---|---:|---:|---|
| 10 | `espresso` | Espresso | Kaffee | `espresso` | 19 | 19 | `standard_19` |
| 20 | `espresso_double` | Espresso doppio | Kaffee | `espresso` | 19 | 19 | `standard_19` |
| 30 | `cafe_creme` | Café Crème | Kaffee | `coffee` | 19 | 19 | `standard_19` |
| 40 | `americano` | Americano | Kaffee | `coffee` | 19 | 19 | `standard_19` |
| 50 | `cappuccino` | Cappuccino | Kaffee | `milk_coffee` | 19 | 19 | `recipe_review` |
| 60 | `latte_macchiato` | Latte Macchiato | Kaffee | `milk_coffee` | 19 | 19 | `recipe_review` |
| 70 | `milk_coffee` | Milchkaffee | Kaffee | `milk_coffee` | 19 | 19 | `recipe_review` |
| 80 | `hot_chocolate` | Heiße Schokolade | Kaffee | `hot_chocolate` | 19 | 19 | `recipe_review` |
| 10 | `tea` | Tee | Tee & Kaltgetränke | `tea` | 19 | 19 | `standard_19` |
| 20 | `fresh_mint_tea` | Frischer Minztee | Tee & Kaltgetränke | `tea` | 19 | 19 | `standard_19` |
| 30 | `water_still` | Wasser still | Tee & Kaltgetränke | `water` | 19 | 19 | `standard_19` |
| 40 | `water_sparkling` | Wasser sprudel | Tee & Kaltgetränke | `water` | 19 | 19 | `standard_19` |
| 50 | `cola` | Cola | Tee & Kaltgetränke | `soft_drink` | 19 | 19 | `standard_19` |
| 60 | `apple_spritzer` | Apfelschorle | Tee & Kaltgetränke | `spritzer` | 19 | 19 | `standard_19` |
| 70 | `orange_juice` | Orangensaft | Tee & Kaltgetränke | `juice` | 19 | 19 | `standard_19` |
| 10 | `croissant` | Croissant | Backwaren | `croissant` | 7 | 7 | `food_7_2026` |
| 20 | `chocolate_croissant` | Schokocroissant | Backwaren | `croissant` | 7 | 7 | `food_7_2026` |
| 30 | `butter_pretzel` | Butterbrezel | Backwaren | `pretzel` | 7 | 7 | `food_7_2026` |
| 40 | `cheese_roll` | Belegtes Brötchen Käse | Backwaren | `sandwich` | 7 | 7 | `food_7_2026` |
| 50 | `ham_roll` | Belegtes Brötchen Schinken | Backwaren | `sandwich` | 7 | 7 | `food_7_2026` |
| 60 | `cake_slice` | Kuchen, Stück | Backwaren | `cake` | 7 | 7 | `food_7_2026` |
| 10 | `breakfast_small` | Frühstück klein | Frühstück & Speisen | `breakfast` | 7 | 7 | `food_7_2026` |
| 20 | `breakfast_large` | Frühstück groß | Frühstück & Speisen | `breakfast` | 7 | 7 | `food_7_2026` |
| 30 | `scrambled_eggs` | Rührei | Frühstück & Speisen | `egg_dish` | 7 | 7 | `food_7_2026` |
| 40 | `daily_soup` | Tagessuppe | Frühstück & Speisen | `soup` | 7 | 7 | `food_7_2026` |

### 4.3 Rezepturprüfung bei Milchgetränken

Für Cappuccino, Latte Macchiato, Milchkaffee und heiße Schokolade ist `19 / 19` der sichtbare
Arbeitsvorschlag. Die Inhouse-Abgabe bleibt als Getränk bei 19 Prozent. Für eine spätere Außer-Haus-
Lieferung muss der Betreiber anhand der dokumentierten Standardrezeptur prüfen, ob die Voraussetzungen
für ein begünstigtes Milchmischgetränk tatsächlich vorliegen.

Der Wizard fragt bei jeder dieser Zeilen:

```text
Außer-Haus-Satz geprüft
Unsere dokumentierte Rezeptur rechtfertigt den ausgewählten Satz.
```

Ohne Einzelbestätigung bleibt „Importieren“ deaktiviert. Eine Namensheuristik darf den Satz niemals
selbständig auf 7 Prozent umstellen.

## 5. Preset `spaeti@1`

### 5.1 Kategorien

| Reihenfolge | `category_key` | Anzeigename | Farbrolle |
|---:|---|---|---|
| 10 | `cold_drinks` | Alkoholfreie Getränke | `blue` |
| 20 | `beer_wine` | Bier & Wein | `indigo` |
| 30 | `snacks_sweets` | Snacks & Süßes | `orange` |
| 40 | `everyday` | Alltag | `gray` |
| 50 | `tobacco` | Tabak | `brown` |

### 5.2 Direkt nutzbare Produkte

`Pfand` ist ein separater Betrag und niemals Teil von `price_cents`. `25` bedeutet 25 Cent
Einwegpfand. Die mit `25` markierten Zeilen unterliegen dem Release-Gate aus Abschnitt 5.4.

| Sort | `item_key` | Produktname | Kategorie | `visual_key` | Pfand | Inhouse | Takeaway | Prüfklasse |
|---:|---|---|---|---|---:|---:|---:|---|
| 10 | `water_still_pet_050` | Wasser still, PET 0,5 l | Alkoholfreie Getränke | `water` | 25 | 19 | 19 | `standard_19` |
| 20 | `water_sparkling_pet_050` | Wasser sprudel, PET 0,5 l | Alkoholfreie Getränke | `water` | 25 | 19 | 19 | `standard_19` |
| 30 | `cola_can_033` | Cola, Dose 0,33 l | Alkoholfreie Getränke | `soft_drink` | 25 | 19 | 19 | `standard_19` |
| 40 | `cola_zero_can_033` | Cola ohne Zucker, Dose 0,33 l | Alkoholfreie Getränke | `soft_drink` | 25 | 19 | 19 | `standard_19` |
| 50 | `orange_soda_can_033` | Orangenlimonade, Dose 0,33 l | Alkoholfreie Getränke | `soft_drink` | 25 | 19 | 19 | `standard_19` |
| 60 | `apple_spritzer_pet_050` | Apfelschorle, PET 0,5 l | Alkoholfreie Getränke | `spritzer` | 25 | 19 | 19 | `standard_19` |
| 70 | `energy_can_025` | Energydrink, Dose 0,25 l | Alkoholfreie Getränke | `energy_drink` | 25 | 19 | 19 | `standard_19` |
| 80 | `orange_juice_carton_100` | Orangensaft, Karton 1,0 l | Alkoholfreie Getränke | `juice` | 0 | 19 | 19 | `standard_19` |
| 10 | `pils_can_050` | Pils, Dose 0,5 l | Bier & Wein | `beer` | 25 | 19 | 19 | `standard_19` |
| 20 | `lager_can_050` | Lager, Dose 0,5 l | Bier & Wein | `beer` | 25 | 19 | 19 | `standard_19` |
| 30 | `radler_can_050` | Radler, Dose 0,5 l | Bier & Wein | `beer` | 25 | 19 | 19 | `standard_19` |
| 40 | `alcohol_free_beer_can_050` | Bier alkoholfrei, Dose 0,5 l | Bier & Wein | `beer` | 25 | 19 | 19 | `standard_19` |
| 50 | `red_wine_bottle_075` | Rotwein, Flasche 0,75 l | Bier & Wein | `wine` | 0 | 19 | 19 | `standard_19` |
| 60 | `white_wine_bottle_075` | Weißwein, Flasche 0,75 l | Bier & Wein | `wine` | 0 | 19 | 19 | `standard_19` |
| 10 | `potato_chips_150` | Kartoffelchips, 150 g | Snacks & Süßes | `chips` | 0 | 7 | 7 | `food_7_2026` |
| 20 | `salted_peanuts_200` | Salzige Erdnüsse, 200 g | Snacks & Süßes | `nuts` | 0 | 7 | 7 | `food_7_2026` |
| 30 | `chocolate_bar` | Schokoriegel | Snacks & Süßes | `chocolate` | 0 | 7 | 7 | `food_7_2026` |
| 40 | `gummy_candy_200` | Fruchtgummi, 200 g | Snacks & Süßes | `gummy_candy` | 0 | 7 | 7 | `food_7_2026` |
| 50 | `cookies_200` | Kekse, 200 g | Snacks & Süßes | `cookies` | 0 | 7 | 7 | `food_7_2026` |
| 60 | `chewing_gum` | Kaugummi | Snacks & Süßes | `gummy_candy` | 0 | 7 | 7 | `food_7_2026` |
| 70 | `ice_pop` | Eis am Stiel | Snacks & Süßes | `ice_cream` | 0 | 7 | 7 | `food_7_2026` |
| 80 | `instant_noodles_cup` | Instantnudeln, Becher | Snacks & Süßes | `instant_meal` | 0 | 7 | 7 | `food_7_2026` |
| 10 | `lighter` | Feuerzeug | Alltag | `lighter` | 0 | 19 | 19 | `standard_19` |
| 20 | `tissues` | Taschentücher | Alltag | `tissues` | 0 | 19 | 19 | `standard_19` |
| 30 | `battery_aa_4` | Batterien AA, 4er | Alltag | `battery` | 0 | 19 | 19 | `standard_19` |
| 40 | `battery_aaa_4` | Batterien AAA, 4er | Alltag | `battery` | 0 | 19 | 19 | `standard_19` |
| 50 | `usb_c_cable` | Ladekabel USB-C | Alltag | `cable` | 0 | 19 | 19 | `standard_19` |

### 5.3 Tabakvorlagen: nicht blind importierbar

Diese drei Zeilen sind Vorlagen, keine fertigen Produkte. Sie sind standardmäßig abgewählt und können
erst ausgewählt werden, nachdem der Betreiber einen konkreten Produktnamen, Packungsinhalt und den auf
der Packung beziehungsweise dem Steuerzeichen ausgewiesenen Preis eingegeben hat.

| Sort | `item_key` | Pflichtformat für den Namen | `visual_key` | MwSt. | Zusätzliche Sperre |
|---:|---|---|---|---:|---|
| 10 | `cigarettes_custom` | `[Marke] [Variante], [Stückzahl]` | `cigarettes` | 19 / 19 | Preis = aufgedruckter Packungspreis |
| 20 | `fine_cut_tobacco_custom` | `[Marke] [Variante], [Gramm]` | `tobacco` | 19 / 19 | Preis = aufgedruckter Packungspreis |
| 30 | `hookah_tobacco_custom` | `[Marke] [Variante], [Gramm]` | `tobacco` | 19 / 19 | Preis = aufgedruckter Packungspreis |

Rechtsgrundlagen und Betriebshinweise:

- [§ 3 TabStG – Kleinverkaufspreis](https://www.gesetze-im-internet.de/tabstg_2009/__3.html)
- [§ 25 TabStG – Packungen und Stückverkauf](https://www.gesetze-im-internet.de/tabstg_2009/__25.html)
- [§ 26 TabStG – Verbot der Abgabe unter Kleinverkaufspreis](https://www.gesetze-im-internet.de/tabstg_2009/__26.html)
- [§ 28 TabStG – Verbot der Abgabe über Kleinverkaufspreis](https://www.gesetze-im-internet.de/tabstg_2009/__28.html)
- [Zoll-Merkblatt: Handel mit Wasserpfeifentabak](https://www.zoll.de/SharedDocs/Downloads/DE/FormulareMerkblaetter/Verbrauchsteuern/Tabaksteuer/Sonstige/1654de_2024.pdf?__blob=publicationFile)

Eine einzelne generische Kachel „Zigaretten“ mit frei gewähltem Preis ist ausdrücklich nicht Teil des
Presets. Auch ein Stückverkauf von Zigaretten wird nicht unterstützt.

### 5.4 Pfand ist ein Release-Gate, kein Produktpreis-Trick

Das aktuelle Produkt-/Order-Modell besitzt kein separates Pfandfeld und keinen Pfandrückgabe-Flow.
Deshalb dürfen die elf mit `deposit_cents: 25` markierten Produkte nicht als „produktionsbereit“
importiert werden, bevor ein eigener, finanziell auditierter Pfand-Pfad umgesetzt und getestet ist.

Rechtlicher Rahmen:

- Bei pfandpflichtigen Einweggetränkeverpackungen sind mindestens 0,25 Euro einschließlich
  Umsatzsteuer zu erheben und bei Rücknahme zu erstatten: [§ 31 VerpackG](https://www.gesetze-im-internet.de/verpackg/__31.html).
- Ein Pfandbetrag ist neben dem Warenpreis auszuweisen und darf nicht in diesen eingerechnet werden:
  [§ 7 PAngV](https://www.gesetze-im-internet.de/pangv_2022/__7.html).

Bis dieser Pfad existiert, gilt:

1. Der Späti-Wizard zeigt das Preset in Preview-/Planungsform.
2. Pfandpflichtige Zeilen sind sichtbar, aber deaktiviert und mit „Pfandfunktion erforderlich“ erklärt.
3. Pfandfreie Artikel und vollständig ausgefüllte Tabakvorlagen dürfen importiert werden.
4. Die öffentliche Produktkommunikation darf den Späti-Preset nicht als vollständig startklar bewerben.

Der separate Pfand-Pfad muss mindestens Warenpreis und Pfand getrennt anzeigen, beide Beträge korrekt
auf Bon/TSE abbilden, eine signierte Pfandrückgabe ohne Löschen oder Überschreiben von Finanzdaten
ermöglichen und Cent-genaue Unit-/Integration-/Compliance-Tests besitzen. Die konkrete finanzielle
Architektur wird in einem eigenen Paket festgelegt; S17B darf sie nicht nebenbei improvisieren.

## 6. Endgültiger `visual_key`-Katalog V1

### 6.1 Datenvertrag

- DB-Feld: `products.visual_key VARCHAR(64) NULL`.
- `NULL` ist ein vollwertiger Zustand und rendert die hochwertige textbasierte Kassenkachel.
- Die DB speichert niemals `SF Symbol`-Namen oder Asset-Pfade.
- Das Backend akzeptiert nur `NULL` oder einen Wert aus dem versionierten V1-Katalog.
- Unbekannte Werte aus einer neueren API-Version rendern defensiv als `generic`; sie dürfen das Decoding
  oder die Kasse nicht abbrechen.
- Ein Schlüssel ändert nach Veröffentlichung nie seine Bedeutung. Neue Motive erhalten neue Schlüssel.
- SF Symbols und Bundle-Assets verwenden Template Rendering; die Kategorie-Farbe liefert den Tint.
- Das Produkt bleibt durch Namen und Preis verständlich. Das Bild ist unterstützend und optional.

### 6.2 Kuratierte Liste

| `visual_key` | Renderer V1 | Renderziel | Semantik/Beispiele |
|---|---|---|---|
| `generic` | SF Symbol | `square.grid.2x2.fill` | bewusster Fallback |
| `shisha` | Bundle-Asset | `product.shisha` | Shisha Klassik/Premium/Fruchtkopf |
| `shisha_refill` | Bundle-Asset | `product.shisha.refill` | Kopfwechsel/Nachfüllung |
| `charcoal` | SF Symbol | `flame.fill` | Kohle |
| `tobacco` | SF Symbol | `leaf.fill` | Fein-/Wasserpfeifentabak |
| `smoking_accessory` | SF Symbol | `wrench.and.screwdriver.fill` | Zubehör |
| `espresso` | SF Symbol | `cup.and.saucer.fill` | Espresso/Doppio |
| `coffee` | SF Symbol | `cup.and.saucer.fill` | schwarzer Kaffee/Americano |
| `milk_coffee` | SF Symbol | `cup.and.saucer.fill` | Cappuccino/Latte/Milchkaffee |
| `tea` | SF Symbol | `mug.fill` | Tee/Minztee |
| `hot_chocolate` | SF Symbol | `mug.fill` | heiße Schokolade |
| `water` | SF Symbol | `waterbottle.fill` | still/sprudel |
| `soft_drink` | SF Symbol | `takeoutbag.and.cup.and.straw.fill` | Cola/Limonade |
| `spritzer` | SF Symbol | `bubbles.and.sparkles.fill` | Schorle |
| `energy_drink` | SF Symbol | `bolt.fill` | Energydrink |
| `juice` | SF Symbol | `drop.fill` | Saft |
| `beer` | SF Symbol | `mug.fill` | Bier/Radler |
| `wine` | SF Symbol | `wineglass.fill` | Rot-/Weißwein |
| `breakfast` | SF Symbol | `sun.horizon.fill` | Frühstück |
| `egg_dish` | SF Symbol | `frying.pan.fill` | Rührei/Eierspeise |
| `soup` | SF Symbol | `takeoutbag.and.cup.and.straw.fill` | Suppe |
| `sandwich` | SF Symbol | `fork.knife` | belegtes Brötchen/Sandwich |
| `croissant` | Bundle-Asset | `product.croissant` | Croissant |
| `pretzel` | Bundle-Asset | `product.pretzel` | Brezel |
| `cake` | SF Symbol | `birthday.cake.fill` | Kuchen/Torte |
| `nachos` | SF Symbol | `fork.knife` | Nachos |
| `chips` | SF Symbol | `takeoutbag.and.cup.and.straw.fill` | Chips |
| `nuts` | SF Symbol | `leaf.circle.fill` | Nüsse |
| `fruit` | SF Symbol | `leaf.fill` | Obst/Obstteller |
| `chocolate` | SF Symbol | `square.grid.3x3.fill` | Schokolade/Riegel |
| `gummy_candy` | SF Symbol | `circle.hexagongrid.fill` | Fruchtgummi/Kaugummi |
| `cookies` | SF Symbol | `circle.grid.2x2.fill` | Kekse |
| `ice_cream` | SF Symbol | `snowflake` | Speiseeis |
| `instant_meal` | SF Symbol | `takeoutbag.and.cup.and.straw.fill` | Instantgericht |
| `cigarettes` | SF Symbol | `shippingbox.fill` | verschlossene Zigarettenpackung |
| `lighter` | SF Symbol | `flame.fill` | Feuerzeug |
| `tissues` | SF Symbol | `shippingbox.fill` | Taschentücher |
| `battery` | SF Symbol | `battery.100percent` | Batterien |
| `cable` | SF Symbol | `cable.connector` | Ladekabel |

Mehrere Schlüssel dürfen in V1 dasselbe SF Symbol verwenden. Die getrennten semantischen Schlüssel
sind trotzdem gewollt: Das Rendering kann später verbessert werden, ohne gespeicherte Produktdaten zu
migrieren.

### 6.3 Bundle-Asset-Regeln

Die vier V1-Assets `product.shisha`, `product.shisha.refill`, `product.croissant` und `product.pretzel`
werden als einfache, monochrome Vektor-Template-Assets erstellt.

- Keine Fotos, Marken, Verläufe, Schatten oder mehrfarbigen Illustrationen.
- Optisches Gewicht auf 20–24 pt an benachbarte SF Symbols angleichen.
- In Light/Dark Mode sowie bei erhöhtem Kontrast mit Kategorie-Tint prüfen.
- Rechte müssen vollständig beim Projekt liegen; keine aus dem Web kopierten Piktogramme.
- Asset fehlt zur Laufzeit: `generic` statt leerer oder abstürzender Kachel.

### 6.4 Vorschlagsheuristik für manuell angelegte Produkte

Die Heuristik ist nur eine Vorbelegung des optionalen Pickers:

1. Name Unicode-normalisieren, kleinschreiben, Diakritika für den Vergleich falten und Mengenangaben
   wie `0,33 l`, `500 ml`, `200 g` aus dem Vergleich entfernen.
2. Ganze Wörter beziehungsweise Phrasen matchen; keine ungesicherten Teilstrings. So darf `tee` nicht
   versehentlich in einem anderen Wort treffen.
3. Die spezifischste Regel gewinnt: `latte macchiato` vor `kaffee`, `cola ohne zucker` vor `cola`.
4. Kategorie als sekundäres Signal verwenden, niemals den MwSt.-Satz.
5. Ohne belastbaren Treffer `NULL` vorschlagen, nicht `generic` in die DB schreiben.
6. Eine Nutzeränderung nie durch eine spätere Namensänderung überschreiben.

Für alle V1-Presetnamen existieren exakte Unit-Test-Fixtures. Zusätzlich sind mindestens diese
Negativfälle zu testen: leerer Name, Emoji, nur Mengenangabe, unbekannte Sprache, sehr langer Name,
Groß-/Kleinschreibung, Umlaute und ähnlich geschriebene Nicht-Treffer.

### 6.5 Accessibility

- In einer Produktkachel ist das Visual dekorativ und für VoiceOver ausgeblendet, weil Produktname und
  Preis bereits die zugängliche Beschriftung bilden.
- Im Visual-Picker erhält jede Auswahl eine lokalisierte Bezeichnung, zum Beispiel „Kaffee“, „Wasser“
  oder „Ohne Symbol“; der technische Key wird nie vorgelesen.
- Auswahl wird zusätzlich mit Checkmark und VoiceOver-Trait kommuniziert, nie nur durch Farbe.
- Jede Auswahlfläche ist mindestens 44 × 44 pt groß; Dynamic Type bis mindestens AX1 darf keine Werte
  abschneiden.

## 7. Versionierte Preset-Struktur

Die Definitionen leben als typisierte, schreibgeschützte Code-Daten, nicht als produktive DB-Seeds.
Vorgesehener Vertrag:

```ts
type VatRate = '7' | '19';
type VatReview =
  | 'standard_19'
  | 'food_7_2026'
  | 'recipe_review'
  | 'printed_price_review';

interface AssortmentPresetProduct {
  item_key: string;
  category_key: string;
  name_de: string;
  sort_order: number;
  price_cents: null;
  vat_rate_inhouse: VatRate;
  vat_rate_takeaway: VatRate;
  vat_review: VatReview;
  visual_key: VisualKey | null;
  deposit_cents: 0 | 25;
  requires_custom_name?: boolean;
  requires_exact_price?: boolean;
}

interface AssortmentPreset {
  preset_id: 'shisha_bar' | 'cafe' | 'spaeti' | 'empty';
  version: 1;
  tax_basis_version: 'de-ust-2026-01';
  categories: readonly AssortmentPresetCategory[];
  products: readonly AssortmentPresetProduct[];
}
```

Die konkrete `VisualKey`-Union wird aus der Liste in Abschnitt 6 generiert oder exhaustiv gegen sie
getestet. Freie Strings im Importpfad sind nicht zulässig.

## 8. Importvertrag und Idempotenz

### 8.1 Geplante Endpunkte

```text
GET  /products/presets
POST /products/presets/import
```

Der POST erhält einen UUID-`Idempotency-Key`-Header und einen vollständig bestätigten Snapshot:

```json
{
  "preset_id": "cafe",
  "preset_version": 1,
  "tax_basis_version": "de-ust-2026-01",
  "vat_confirmed": true,
  "items": [
    {
      "item_key": "espresso",
      "name": "Espresso",
      "price_cents": 280,
      "vat_rate_inhouse": "19",
      "vat_rate_takeaway": "19",
      "visual_key": "espresso"
    }
  ]
}
```

Der Server validiert Preset, Version und Item-Keys gegen seine eigene Definition. Er vertraut nicht auf
vom Client erfundene Presetzeilen. Änderbar sind nur die ausdrücklich erlaubten Felder Name, Preis,
bestätigte Steuersätze, Auswahl, Zielkategorie und optionales Visual.

### 8.2 Persistente Herkunft

Mindestens folgende Herkunftsdaten werden für Kategorien und Produkte gespeichert:

```text
origin_preset_id
origin_preset_version
origin_item_key beziehungsweise origin_category_key
```

Für Produkte gilt ein Unique-Constraint auf
`(tenant_id, origin_preset_id, origin_item_key)`. Ein Retry, Doppeltap oder erneuter Import einer
späteren Preset-Version erzeugt für denselben stabilen Item-Key kein Duplikat und überschreibt keine
Betreiberänderung. Neue Item-Keys einer späteren Version können separat angeboten werden.

Namensgleichheit ist nie ein automatischer Merge-Schlüssel. Existiert ein manuell angelegtes Produkt
gleichen Namens, muss der Wizard „Vorhandenes verwenden“, „Trotzdem neu anlegen“ oder „Abwählen“
anbieten.

### 8.3 Gemeinsamer GoBD-konformer Produktservice

Controller und Preset-Import dürfen keine eigenen Produkt-INSERTs besitzen. Beide verwenden denselben
Service. Weil `product_price_history` über einen separaten INSERT-only-DB-User geschrieben wird, darf
ein Produkt bei einem Fehler zwischen Produktanlage und Historieneintrag nie verkaufsfähig werden.

Robuster Ablauf:

1. Produkt tenant-sicher und zunächst `is_active = FALSE` mit stabiler Herkunft anlegen oder finden.
2. Initialen `product_price_history`-Eintrag über den vorgeschriebenen Audit-DB-Pfad schreiben.
3. Existenz und exakte Werte des Historieneintrags verifizieren.
4. Erst danach das Produkt aktivieren.
5. Bei einem Fehler bleibt es inaktiv; der Retry repariert denselben Herkunftsdatensatz, statt einen
   zweiten anzulegen.
6. Audit-Log enthält Preset-ID/-Version, bestätigenden Nutzer, Steuerbasis und einen Snapshot der
   importierten Werte.

Dieser Ablauf muss auch den normalen `POST /products`-Pfad härten. Ein erfolgreicher API-Response ohne
initiale Preis-/Steuerhistorie ist nicht zulässig.

### 8.4 Tenant-Isolation und Rollen

- Presets lesen: authentifizierte Rollen, da die Daten selbst global/statisch sind.
- Importieren: nur `owner` und `manager`.
- `tenant_id` ausschließlich aus dem JWT; nie aus Body, URL oder Preset.
- Jede Herkunfts-, Kategorie-, Produkt- und History-Abfrage enthält die Tenant-Bedingung.
- Fremde Kategorie-/Produkt-IDs liefern 404 statt Informationen über einen anderen Tenant.

## 9. Wizard: festgelegter Ablauf

1. **Paket wählen:** Shisha-Bar, Café, Späti oder Leer starten; Anzahl Kategorien/Produkte und der
   Pfandhinweis sind vor Auswahl sichtbar.
2. **Auswahl anpassen:** Kategorien links, Produkte rechts; alles vorausgewählt außer Tabakvorlagen und
   aktuell blockierten Pfandzeilen.
3. **Namen und Preise:** kompakte Tabelle, direkte Zeilennavigation, deutscher Geldparser, Cent-Integer;
   kein ausgewähltes Produkt darf leer oder `0,00 €` sein.
4. **MwSt. prüfen:** verständliche Gruppen „Speisen 7 %“, „Getränke/sonstige 19 %“ und separat jede
   `recipe_review`-/`printed_price_review`-Zeile.
5. **Visuals prüfen:** echte Kassenkachel-Vorschau; „Ohne Symbol“ ist eine gleichwertige Auswahl.
6. **Vorschau:** Kategorie- und Produktreihenfolge entspricht exakt der späteren Kasse; Summe der
   ausgewählten Produkte und Warnungen sichtbar.
7. **Import:** eine primäre Aktion, während Request gesperrt; Retry nutzt denselben Idempotency-Key.
8. **Ergebnis:** importiert/übersprungen/zu prüfen getrennt anzeigen und direkt „Sortiment öffnen“ oder
   „Kasse ansehen“ anbieten.

Zurücknavigation bewahrt Eingaben. Verlassen mit Änderungen erfordert eine System-Confirmation. Fehler
werden an der betroffenen Zeile erklärt; bereits erfolgreich angelegte Produkte werden bei Retry nicht
dupliziert.

## 10. Strukturierter Implementierungsplan

### Paket 0 – fachliche Gates

- [ ] Pilotbetrieb bestätigt Produktnamen, Gebinde und Reihenfolge des `shisha_bar@1`-Presets.
- [ ] Steuerberater bestätigt die Matrix dieses Dokuments schriftlich, besonders Milchmischgetränke,
      Shisha-Leistung und spätere Außer-Haus-Nutzung.
- [ ] Produktentscheidung zum separaten Pfand-Paket treffen; Späti-Pfandzeilen bleiben bis dahin
      release-blockiert.
- [ ] Rechtsstand unmittelbar vor Implementierungsbeginn erneut prüfen; bei Änderung neue
      `tax_basis_version` anlegen.

### Paket 1 – S17A-Datenfundament

- [ ] Produkt-`sort_order` migrieren und tenant-sicher persistieren.
- [ ] Kategorie-`sort_order` vollständig bis SwiftUI durchreichen.
- [ ] Management-Abfrage aktive und inaktive Produkte; Kassenabfrage weiterhin active-only.
- [ ] Kombinierten Bereich „Sortiment“ inklusive Reaktivierung, Suche, Filter, Reorder und Vorschau bauen.
- [ ] Kategorie-Löschcopy an tatsächliches 409-Verhalten angleichen.
- [ ] S17A-Integration-, Tenant-, Decoding- und Sortiertests abschließen.

### Paket 2 – S17B-Schema und Verträge

- [ ] `visual_key` nullable ergänzen und Whitelist validieren.
- [ ] stabile Preset-Herkunft plus Unique-Constraints für Idempotenz ergänzen.
- [ ] Preset-Version und Steuerbasis in Audit-Snapshots erfassen.
- [ ] TypeScript- und Swift-Modelle tolerant für unbekannte zukünftige Visuals machen.
- [ ] Migration rückwärtskompatibel halten; bestehende Produkte bleiben mit `visual_key = NULL` gültig.

### Paket 3 – Presetdefinitionen und Service

- [ ] Die Tabellen aus Abschnitt 3 bis 5 exakt als readonly Daten abbilden.
- [ ] Build-Time-Tests auf eindeutige IDs, Sortierungen, gültige Steuersätze, bekannte Visuals und
      Produktanzahlen schreiben.
- [ ] Gemeinsamen Produktservice mit inaktiv → History → aktiv umsetzen.
- [ ] Endpunkte aus Abschnitt 8 mit Zod-Validierung, Rollenprüfung, Tenant-Isolation und Idempotenz bauen.
- [ ] Failure-Injection zwischen Produktanlage, History und Aktivierung testen.

### Paket 4 – SwiftUI-Wizard

- [ ] Native Navigation/Sets aus `DESIGN.md` verwenden; keine Web-artigen Custom Controls.
- [ ] Paket-, Auswahl-, Preis-, MwSt.-, Visual-, Vorschau- und Ergebnis-Schritt implementieren.
- [ ] Fokusführung und Zifferneingabe für schnelle Preiseingabe auf einem Landscape-iPad optimieren.
- [ ] `recipe_review`, Tabak- und Pfand-Sperren klar, ruhig und handlungsfähig darstellen.
- [ ] Abbruch, Zurück, Retry, Servervalidierung und partielle Fehler vollständig behandeln.

### Paket 5 – Visuals V1

- [ ] Exhaustiven `ProduktVisualCatalog` mit allen 39 Keys anlegen.
- [ ] Vier eigene monochrome Assets erstellen und gegen SF-Symbol-Gewicht prüfen.
- [ ] Name-zu-Visual-Heuristik mit Wortgrenzen und Unit Tests umsetzen.
- [ ] Kassenkacheln mit Visual und `NULL`-Visual gleichwertig gestalten.
- [ ] Light/Dark, erhöhter Kontrast, Dynamic Type, VoiceOver und Reduce Motion prüfen.

### Paket 6 – Abnahme und Dokumentation

- [ ] Frischer Tenant: mindestens 3 Kategorien und 15 verkaufsfertige Produkte in unter 10 Minuten.
- [ ] Doppeltap, Timeout und Retry erzeugen keine doppelten Kategorien/Produkte/History-Zeilen.
- [ ] Jedes aktive importierte Produkt besitzt exakt den erwarteten initialen History-Eintrag.
- [ ] Bestehende manuelle Produkte werden weder überschrieben noch über Namen still gemergt.
- [ ] Sortierung ist nach App-/Server-Neustart identisch mit Vorschau und Kasse.
- [ ] Unbekannter/fehlender `visual_key` beeinträchtigt weder Decoding noch Verkauf.
- [ ] Kompletter Verkauf funktioniert ohne Visuals.
- [ ] Späti-Pfandzeilen bleiben gesperrt, solange der separate Pfad nicht abgenommen ist.
- [ ] `CLAUDE.md`, `OFFEN.md`, `ROADMAP.md`, `docs/testkonzept.md` und API-Dokumentation aktualisieren.
- [ ] Typecheck, Unit-/Compliance-, Integration- und iOS-Tests vollständig grün.

## 11. Verbindliche Testmatrix

### Backend Unit

- Alle `preset_id`/`item_key`/`category_key` innerhalb ihres Scopes eindeutig.
- Exakte Counts: Shisha-Bar 4/21, Café 4/25, Späti 5/27 plus 3 gesperrte Vorlagen, Leer 0/0.
- Jede Produktzeile referenziert eine vorhandene Kategorie und einen bekannten `visual_key`.
- Nur `7` oder `19`; alle `recipe_review`-Produkte stehen in der definierten Allowlist.
- `deposit_cents` ausschließlich 0 oder 25; genau elf Späti-Produkte tragen 25.
- Sort-Order pro Kategorie eindeutig und deterministisch.
- Namensheuristik inklusive Negativfällen aus Abschnitt 6.4.

### Backend Integration

- Frischer Tenant importiert Auswahl exakt einmal und mit initialer History.
- Derselbe Idempotency-Key, neuer Key mit identischem Preset sowie paralleler Doppeltap duplizieren nichts.
- Retry nach erzwungenem History-Fehler repariert den inaktiven Datensatz und aktiviert ihn erst danach.
- Zweiter Tenant kann dasselbe Preset unabhängig importieren; keine ID oder Zeile ist tenant-übergreifend
  sichtbar.
- Staff darf lesen, aber nicht importieren; Owner/Manager dürfen importieren.
- Ungültiger Preset-/Item-/Visual-Key, Float-Preis, negativer Preis, `0` bei ausgewählter Zeile und
  fehlende Steuerbestätigung werden abgewiesen.
- Späti-Pfandzeile ohne freigegebene Pfand-Capability wird serverseitig abgewiesen, nicht nur in der UI.

### iOS Unit

- Decoding aller vier Presets und aller 39 Visual-Keys.
- Unbekannter Key und `null` führen zum Fallback, nicht zum Decode-Fehler.
- Sortierung entspricht Kategorie- und Produkt-`sort_order` mit stabilem Tie-Breaker.
- Geldparser liefert nur Cent-Integer; leere/negative/ungültige Eingabe blockiert.
- Review-State kann Standardzeilen gesammelt, Risikozellen aber nur einzeln bestätigen.
- Ein geänderter Produktname überschreibt keine manuelle Visual-Auswahl.

### iOS UI/Accessibility

- Kompletter Café-Import in Standardgröße und AX1.
- VoiceOver-Reihenfolge: Paket → Auswahl → Preis → Steuer → Visual → Vorschau → Import.
- Light/Dark und erhöhter Kontrast; Visuals sind nie die einzige Unterscheidung.
- 44-pt-Ziele, Landscape-Safe-Areas, Hardware-/Software-Tastatur und Reduce Motion.
- Import-Timeout mit sicherem Retry sowie verständliches Ergebnis für importiert/übersprungen/gesperrt.

## 12. Definition of Done für diese Spezifikation

S17B ist erst abgeschlossen, wenn:

- exakt die V1-Daten dieses Dokuments implementiert oder eine Änderung bewusst versioniert wurde;
- jede Steuerannahme vor Import sichtbar bestätigt und auditierbar gespeichert wird;
- kein Produktionspreis aus Test-/Seed-Daten stammt;
- Idempotenz auf Datenbankebene, nicht nur durch einen deaktivierten Button, erzwungen wird;
- der gemeinsame Produktservice niemals ein aktives Produkt ohne initiale Preis-/Steuerhistorie hinterlässt;
- Visuals vollständig optional, zugänglich und für unbekannte zukünftige Werte fehlertolerant sind;
- das Späti-Preset Pfand nicht in den Warenpreis versteckt und bis zur separaten Freigabe korrekt sperrt;
- alle Tests aus Abschnitt 11 sowie die globale Definition of Done aus `CLAUDE.md` grün sind;
- Steuerberaterfreigabe und Pilotabnahme mit Datum/Version dokumentiert sind.

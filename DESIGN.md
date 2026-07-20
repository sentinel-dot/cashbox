---
name: "cashbox"
description: "Der ruhige Tresen: eine Apple-native, futuristisch-minimale Gastrokasse."
colors:
  canvas-light: "#F4F6F1"
  canvas-dark: "#121410"
  surface-light: "#FFFFFF"
  surface-dark: "#1B1E17"
  surface-muted-light: "#ECEFE6"
  surface-muted-dark: "#262A20"
  ink-light: "#1A1F17"
  ink-dark: "#F1F3EC"
  ink-secondary-light: "#596052"
  ink-secondary-dark: "#A2AA95"
  border-light: "#DDE2D4"
  border-dark: "#31362B"
  ledger-green-light: "#4A7310"
  ledger-green-dark: "#6D9A28"
  ledger-soft-light: "#EDF3DE"
  ledger-soft-dark: "#232B15"
  ledger-text-light: "#3C5E0C"
  ledger-text-dark: "#AECB6E"
  ledger-pressed-light: "#3C5E0C"
  ledger-pressed-dark: "#587F1D"
  night-olive: "#1C2413"
  night-olive-dark: "#141A0D"
  brand-leaf: "#AECB6E"
  brass-light: "#9A6A0B"
  brass-dark: "#D9AC46"
  brass-soft-light: "#F8F0DC"
  brass-soft-dark: "#2C240E"
  brass-text-light: "#7C5507"
  brass-text-dark: "#E2BE67"
  danger-light: "#BC3A2B"
  danger-dark: "#E1745F"
  danger-soft-light: "#FAECE9"
  danger-soft-dark: "#371711"
  danger-text-light: "#9E2F22"
  danger-text-dark: "#EE9C86"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "40pt"
    fontWeight: 700
  title:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "26pt"
    fontWeight: 700
  heading:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "20pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "17pt"
    fontWeight: 400
  body-strong:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "17pt"
    fontWeight: 600
  subheadline:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "15pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "13pt"
    fontWeight: 500
  label:
    fontFamily: "SF Pro, -apple-system, sans-serif"
    fontSize: "12pt"
    fontWeight: 600
    letterSpacing: "0.7pt"
  money:
    fontFamily: "SF Rounded, SF Pro Rounded, -apple-system, sans-serif"
    fontSize: "17pt"
    fontWeight: 600
    fontFeature: "tabular-nums"
  money-display:
    fontFamily: "SF Rounded, SF Pro Rounded, -apple-system, sans-serif"
    fontSize: "40pt"
    fontWeight: 700
    fontFeature: "tabular-nums"
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "17pt"
    fontWeight: 400
rounded:
  control: "8pt"
  brand-mark: "9pt"
  input: "10pt"
  button: "10pt"
  quick-banner: "12pt"
  pin-row: "12pt"
  card: "14pt"
  app-shell: "16pt"
  pill: "100pt"
spacing:
  hairline: "1pt"
  micro: "3pt"
  xs: "6pt"
  sm: "8pt"
  compact: "10pt"
  md: "12pt"
  field-inline: "14pt"
  lg: "16pt"
  card: "20pt"
  page: "24pt"
  roomy: "32pt"
components:
  button-primary:
    backgroundColor: "{colors.ledger-green-light}"
    textColor: "{colors.surface-light}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.button}"
    padding: "0 24pt"
    height: "52pt"
  button-primary-active:
    backgroundColor: "{colors.ledger-pressed-light}"
    textColor: "{colors.surface-light}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.button}"
    padding: "0 24pt"
    height: "52pt"
  button-secondary:
    backgroundColor: "{colors.surface-muted-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.button}"
    padding: "0 24pt"
    height: "52pt"
  button-destructive:
    backgroundColor: "{colors.danger-soft-light}"
    textColor: "{colors.danger-text-light}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.button}"
    padding: "0 24pt"
    height: "52pt"
  card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.card}"
    padding: "20pt"
  input:
    backgroundColor: "{colors.canvas-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.body}"
    rounded: "{rounded.input}"
    padding: "0 14pt"
    height: "50pt"
  nav-selected:
    backgroundColor: "{colors.ledger-soft-light}"
    textColor: "{colors.ledger-text-light}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.button}"
    padding: "0 12pt"
    height: "46pt"
  status-payment:
    backgroundColor: "{colors.brass-soft-light}"
    textColor: "{colors.brass-text-light}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: "6pt 11pt"
---

# Design System: cashbox

## 1. Overview

**Creative North Star: "Der ruhige Tresen"**

cashbox wirkt wie ein präzises Werkzeug auf einem aufgeräumten, modernen Tresen: Apple-nativ, futuristisch-minimal und so ruhig, dass der Betreiber jederzeit erkennt, was zählt. Die Zukunftsqualität entsteht aus Klarheit, unmittelbarer Reaktion und sauberer Systemintegration – nicht aus Neon, Effektschichten oder erfundenen Bedienmetaphern.

Das bestehende Ledger-Green-System bleibt die funktionale Basis, wird aber bewusst sparsam eingesetzt. Fast alle Flächen sind olivgetönte Neutrals; Grün markiert Primäraktion, Auswahl und Geldzustand, Brass eine angeforderte Zahlung oder Warnung, Rot ausschließlich Fehler und destruktive Vorgänge. Lebendigkeit kommt aus taktilen Press-Zuständen, flüssiger Systembewegung, Haptik und wenigen klaren Peak Moments. Weitere Farbe darf später ergänzt werden, aber nur als semantisch begründete Rolle.

Das System lehnt laute Lieferdienst-Optik, überladenes ERP, sterile Behördenoberflächen und foto-lastige Menügrids ab. Es ist dicht genug für professionelle Arbeit, großzügig genug für Touch und eigenständig genug, um nicht wie ein graues Standard-Adminpanel zu wirken.

**Key Characteristics:**

- Native iPadOS-Präzision für einen festen Landscape-Kassenplatz.
- Flache, tonal geschichtete Oberflächen mit 1-pt-Hairlines statt Schatten.
- Restrained Color: ein seltener Ledger-Green-Akzent plus Brass und Rot mit festen Rollen.
- SF Pro für Bedienung, SF Rounded mit Tabellenziffern für Geld, SF Mono für Belegdaten.
- Ruhige Grundfläche, lebendige Reaktion: Press, Auswahl, Erfolg und Störung sind spürbar.
- Touch-first, VoiceOver-fähig, Dark Mode und Reduce Motion als Systemzustände.

## 2. Colors

Die Palette verbindet kühle Apple-Präzision mit leicht warmen Oliv-Neutrals; Akzentfarbe muss immer eine operative Bedeutung verdienen.

### Primary

- **Ledger Green** (`#4A7310` hell / `#6D9A28` dunkel): Primäraktionen, aktuelle Auswahl, Umsatz und aktive Geldzustände.
- **Ledger Wash** (`#EDF3DE` hell / `#232B15` dunkel): ruhige Auswahl- und Erfolgsflächen ohne vollflächige Sättigung.
- **Ledger Ink** (`#3C5E0C` hell / `#AECB6E` dunkel): Text und SF Symbols auf Ledger Wash; nicht als Fließtextfarbe verwenden.
- **Night Olive** (`#1C2413` hell / `#141A0D` dunkel): konzentrierte Brand-Fläche für Login und Onboarding; kein allgemeiner Kartenhintergrund.

### Secondary

- **Brass Signal** (`#9A6A0B` hell / `#D9AC46` dunkel): angeforderte Zahlung, Trial-Hinweise und Warnzustände.
- **Brass Wash** (`#F8F0DC` hell / `#2C240E` dunkel): Hintergrund zu Brass Signal, damit Aufmerksamkeit entsteht, ohne zu alarmieren.
- **Brass Ink** (`#7C5507` hell / `#E2BE67` dunkel): Text und Symbole auf Brass Wash.

### Tertiary

- **Register Red** (`#BC3A2B` hell / `#E1745F` dunkel): ausschließlich Storno, Löschen und Fehler.
- **Register Red Wash** (`#FAECE9` hell / `#371711` dunkel): destruktive Buttons und Fehlermeldungsflächen.
- **Register Red Ink** (`#9E2F22` hell / `#EE9C86` dunkel): lesbarer Fehlertext und Symbole auf der Wash-Fläche.

### Neutral

- **Ledger Paper** (`#F4F6F1` hell / `#121410` dunkel): App-Canvas und Eingabegrund.
- **Porcelain Surface** (`#FFFFFF` hell / `#1B1E17` dunkel): Karten, Sidebar, Topbar und Sheets.
- **Quiet Surface** (`#ECEFE6` hell / `#262A20` dunkel): Sekundärbuttons, inaktive Controls und Skeletons.
- **Register Ink** (`#1A1F17` hell / `#F1F3EC` dunkel): primärer Text.
- **Muted Ink** (`#596052` hell / `#A2AA95` dunkel): Hilfstext, Labels und inaktive Navigation.
- **Hairline Olive** (`#DDE2D4` hell / `#31362B` dunkel): 1-pt-Trenner und Kartenränder.

### Named Rules

**The Earned Color Rule.** Ledger Green markiert nur Primäraktion, Auswahl oder Geld; Brass nur offene Aufmerksamkeit; Rot nur Gefahr. Neue Farben brauchen vor der Einführung eine exklusive semantische Rolle.

**The Quiet Future Rule.** Futuristisch bedeutet präzise, reaktionsschnell und systemnah – niemals Neonverlauf, dekoratives Leuchten oder handgebautes Glas.

## 3. Typography

**Display Font:** SF Pro mit dem iPadOS-Systemfallback

**Body Font:** SF Pro mit dem iPadOS-Systemfallback
**Label/Mono Font:** SF Pro für Labels, SF Mono für Beleg- und Systemdaten, SF Rounded für Geld

**Character:** Eine einzige Apple-native Schriftfamilie hält die Oberfläche ruhig und vertraut. Geld bekommt mit SF Rounded und Tabellenziffern eine eigene, warme Präzision, ohne eine dekorative Zweitschrift einzuführen.

### Hierarchy

- **Display** (Bold, 40 pt, Dynamic Type relativ zu Large Title): große Geldbeträge und wenige Peak Moments.
- **Headline** (Bold, 26 pt): Seitentitel und primäre Sheet-Aufgaben.
- **Title** (Semibold, 20 pt): Kartenüberschriften, Dialogtitel und wichtige Abschnittseinstiege.
- **Body** (Regular/Medium/Semibold, 17 pt): Standardtext, Bedienlabels und Buttons.
- **Subheadline** (Regular/Medium/Semibold, 15 pt): sekundäre Informationen und kompakte Zeilen.
- **Caption** (Medium/Semibold, 13 pt): Metadaten, Status und Hilfstexte.
- **Label** (Semibold, 12 pt, 0.7 pt Tracking, uppercase): Abschnittslabels in Sidebar und Formularen; nie für Sätze.
- **Money** (SF Rounded Semibold/Bold, 17–40 pt, tabular figures): alle Beträge, KPIs und Kassensummen.

### Named Rules

**The System Type Rule.** Keine Display-Schrift, keine hart codierten Font-Sonderwege und keine Web-Typografie. Alle UI-Texte laufen durch `dsFont`, alle Beträge durch die Money-Tokens.

**The Stable Money Rule.** Beträge nutzen Tabellenziffern und eine gemeinsame deutsche Euroformatierung, damit Listen fluchten und Zahlen bei Updates nicht springen.

## 4. Elevation

cashbox ist flach und tonal geschichtet. Karten, Sidebar, Topbar und Sheets werden durch Canvas-Kontrast, Porcelain/Quiet Surfaces und 1-pt-Hairlines getrennt; Standardkarten haben ausdrücklich keinen Schatten. Native iPadOS-Sheets und Systemmaterialien dürfen ihre plattformeigene Tiefe behalten. Eigengebaute Drop-Shadows, Glows oder Glassmorphism-Layer gehören nicht zum System.

### Named Rules

**The Flat Counter Rule.** Flächen liegen ruhig auf dem Tresen. Tiefe entsteht nur durch Systemmodalität, Tonwert und Hairline – nicht durch dekorative Schatten.

## 5. Components

Komponenten fühlen sich taktil und selbstbewusst an: vertraute Formen, klare Zustände, kurze Reaktion und keine erfundenen Affordanzen.

### Buttons

- **Shape:** kontrolliert gerundet (10 pt), Standardhöhe 52 pt, mindestens 44 × 44 pt Trefferfläche.
- **Primary:** Ledger Green mit weißem 17-pt-Semibold-Label; horizontal 24 pt bei intrinsischer Breite, sonst volle Containerbreite.
- **Pressed / Focus:** Press skaliert auf 0.985 und wechselt in 100 ms zu Ledger Pressed. Nativer Fokus und Accessibility-Fokus bleiben erhalten.
- **Secondary:** Quiet Surface mit Register Ink; gleiche Form, Typografie und Reaktion wie Primary.
- **Destructive:** Register Red Wash mit Register Red Ink; Rot nie für neutrale Abbrechen-Aktionen verwenden.
- **Disabled:** 45 % Deckkraft bei unveränderter Geometrie; eine deaktivierte Primäraktion darf nicht wie eine alternative Aktion aussehen.

### Chips

- **Style:** `DSPill` nutzt Capsule-Geometrie, 11 pt horizontal und 6 pt vertikal, 13-pt-Semibold sowie optional einen 7-pt-Statuspunkt.
- **State:** frei ist neutral, besetzt/aktiv nutzt Ledger Wash, Zahlung angefordert nutzt Brass Wash. Text und Symbol wiederholen die Bedeutung der Farbe.
- **Segmented Control:** 3-pt-Inset auf Quiet Surface; Auswahl liegt als Porcelain Surface mit 1-pt-Hairline und Ledger Ink darüber.

### Cards / Containers

- **Corner Style:** 14 pt für Standardkarten, 16 pt nur für den App-Shell-Rahmen.
- **Background:** Porcelain Surface auf Ledger Paper; Quiet Surface für sekundäre Unterebenen.
- **Shadow Strategy:** keine Schatten; 1-pt-Hairline Olive trennt Karte und Canvas.
- **Internal Padding:** 20 pt Standard, 24 pt Seitenrand für Hauptinhalte.

### Inputs / Fields

- **Style:** 50 pt hoch, 10-pt-Radius, 14 pt horizontal, Ledger Paper beziehungsweise Porcelain Surface mit 1-pt-Hairline.
- **Focus:** 1.5-pt-Ledger-Green-Rand in 120 ms; Layout und Feldhöhe bleiben stabil.
- **Error / Disabled:** 1.5-pt-Register-Red-Rand plus konkrete Fehlermeldung darunter; Farbe nie als einzige Erklärung.

### Navigation

- **Style:** feste 60-pt-Topbar und 252-pt-Sidebar für Landscape-iPad. SF Symbols, 46-pt-Navigationszeilen und gruppierte Uppercase-Labels erzeugen vertraute Hierarchie.
- **Default / Active:** inaktiv Muted Ink auf Porcelain Surface; aktiv Ledger Wash mit Ledger Ink und Semibold-Text. Keine farbige Seitenkante und kein Schatten.
- **Modality:** fokussierte Aufgaben laufen als native Sheets, immersive Kassen- und Bestellabläufe als Full-Screen-Cover. Dirty Forms blockieren versehentliches Verwerfen.

### Success Moment

`DSSuccessCheckmark` ist der bewusste Peak Moment: ein gezeichneter Ledger-Haken auf Ledger Wash, begleitet von Erfolgshaptik, wenn Hardware sie unterstützt. Bei Reduce Motion erscheint er ohne Zeichenanimation. Solche Momente sind Zahlung und korrektem Kassenabschluss vorbehalten.

## 6. Do's and Don'ts

### Do:

- **Do** Systemtypografie, SF Symbols, native Sheets und bekannte iPadOS-Interaktionen als Basis verwenden.
- **Do** mindestens 44 × 44 pt große Trefferflächen, auch wenn das sichtbare Symbol kleiner ist.
- **Do** Ledger Green (`#4A7310` / `#6D9A28`) selten und nur für Primäraktion, Auswahl oder Geldzustand einsetzen.
- **Do** Lebendigkeit durch eindeutige Press-Zustände, Haptik, Skeletons und wenige Success Moments erzeugen.
- **Do** Dark Mode, VoiceOver, AX1 Dynamic Type und Reduce Motion bei jeder neuen Komponente mitdenken.
- **Do** Status mit Farbe, SF Symbol und verständlichem Text gemeinsam ausdrücken.
- **Do** weitere Farbe erst ergänzen, wenn sie eine neue, exklusive semantische Rolle besitzt.

### Don't:

- **Don't** eine laute Lieferdienst-Optik mit konkurrierenden Farben, Badges und Aktionsreizen bauen.
- **Don't** ein überladenes ERP oder All-in-one-Dashboard durch dichte, gleichgewichtige Panels imitieren.
- **Don't** eine sterile Behörden- oder Bankoberfläche aus grauen Tabellen ohne Hierarchie erzeugen.
- **Don't** eine foto-lastige Speisekarte zum Standard für das interne POS-Grid machen.
- **Don't** dekorativen Futurismus mit Neonverläufen, handgebautem Glas oder orbitalen Dashboard-Metaphern einsetzen.
- **Don't** Geräte-, Terminal- oder Systemzustände vortäuschen oder internen Phasenjargon anzeigen.
- **Don't** Minimalismus als leblose generische Graufläche missverstehen; Rhythmus, Hierarchie und gezielte Rückmeldung bleiben Pflicht.
- **Don't** Schatten, dicke Farbstreifen, eigenwillige Scrollbars oder Web-Controls zur Dekoration einführen.
- **Don't** Status allein über Farbe oder Bewegung vermitteln.

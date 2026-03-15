# Kassensystem — Design System

> Stack: SwiftUI (iOS/iPadOS)  
> Basis-Screen: Tischübersicht  
> Stand: Final abgenommen

---

## 1. Typografie

**Font:** Plus Jakarta Sans  
Import: `https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600`

| Verwendung | Größe | Gewicht |
|---|---|---|
| Topbar App-Name | 14px | 600 |
| Nav-Item | 12px | 500 (aktiv: 600) |
| KPI-Wert (Sidebar) | 18px | 600 |
| KPI-Label | 9px | 400, uppercase, letter-spacing 0.6px |
| Tischname (Kachel) | 14px | 600 |
| Betrag (Kachel) | 22px | 600, letter-spacing -0.5px |
| Meta-Zeile (Kachel) | 11px | 400 |
| Badge-Text | 10px | 600 |
| Zone-Pills | 11px | 600 |
| Session-Chip (Topbar) | 11px | 600 |
| Schnellkasse Label | 13px | 600 |
| Schnellkasse Sub | 10px | 400 |
| Section-Header (Nav) | 9px | 400, uppercase, letter-spacing 0.8px |

---

## 2. Farben

### Light Mode

| Token | Hex | Verwendung |
|---|---|---|
| `--bg` | `#f5f4f1` | App-Hintergrund |
| `--sur` | `#ffffff` | Karten, Sidebar, Topbar |
| `--sur2` | `#eceae5` | Inaktive Chips, Trennflächen |
| `--text` | `#1a1a1f` | Primärtext |
| `--text2` | `#9a98a8` | Sekundärtext, Labels, Meta |
| `--brd` | `rgba(26,26,31,0.08)` | Alle Borders |
| `--acc` | `#1a6fff` | Akzentfarbe (Electric Blue) |
| `--acc-bg` | `#e8f0ff` | Akzent-Hintergrund (Chips, Nav aktiv) |
| `--acc-t` | `#0a3dbf` | Akzent-Text auf hellem Grund |

### Dark Mode

| Token | Hex | Verwendung |
|---|---|---|
| `--bg` | `#13131a` | App-Hintergrund |
| `--sur` | `#1c1c26` | Karten, Sidebar, Topbar |
| `--sur2` | `#252535` | Inaktive Chips, Trennflächen |
| `--text` | `#eeeef8` | Primärtext |
| `--text2` | `#6a6888` | Sekundärtext |
| `--brd` | `rgba(238,238,248,0.07)` | Alle Borders |
| `--acc` | `#4d8fff` | Akzentfarbe (aufgehellt für dark) |
| `--acc-bg` | `#0d1f50` | Akzent-Hintergrund |
| `--acc-t` | `#90bbff` | Akzent-Text auf dunklem Grund |

### Status-Farben (Tischstatus)

| Status | BG Light | Text Light | BG Dark | Text Dark |
|---|---|---|---|---|
| Frei | `#e8f5ec` | `#1a5c30` | `#0d2818` | `#60d080` |
| Besetzt | `#eef4ff` | `#0a3dbf` | `#0d1a40` | `#90bbff` |
| Zahlung | `#fff8e0` | `#8a6000` | `#281e08` | `#f0c060` |

### Akzent-Streifen (linker Rand Kachel)

| Status | Farbe |
|---|---|
| Besetzt | `#1a6fff` (Akzentblau) |
| Zahlung | `#d4a017` (Bernstein) |
| Frei | kein Streifen |

---

## 3. Layout & Abstände

### Shell
- `border-radius: 18px`
- Mindesthöhe: 580px (iPad-Ansicht)

### Topbar
- Höhe: 52px
- Padding: `0 20px`
- `border-bottom: 1px solid var(--brd)`

### Sidebar (Navigation)
- Breite: 200px
- `border-right: 1px solid var(--brd)`
- KPIs am unteren Rand mit `border-top: 1px solid var(--brd)`

### Zonen-Bar (unter Topbar im Content-Bereich)
- Padding: `10px 16px`
- `border-bottom: 1px solid var(--brd)`

### Tisch-Grid
- Spalten: **3** (repeat(3, minmax(0, 1fr)))
- Gap: `12px`
- Padding: `16px`

---

## 4. Komponenten

### Tischkachel

Struktur (3 Zeilen, flex-direction column, gap 10px):

```
┌─────────────────────────────────┐
│ Tisch 1          [● Besetzt]    │  ← Zeile 1: Name + Badge
│                                 │
│ 42,50 €                         │  ← Zeile 2: Betrag (allein)
│                                 │
│ ─────────────────────────────── │
│ 38 min  ·  4 Positionen         │  ← Zeile 3: Meta (border-top)
└─────────────────────────────────┘
```

CSS-Details:
- `border-radius: 14px`
- `border: 1px solid var(--brd)`
- `padding: 14px`
- Aktiver linker Rand: `border-left: 3px solid [Statusfarbe]`
- `overflow: hidden`

**Zeile 1 (Name + Badge):**
- `display: flex; justify-content: space-between; align-items: center; gap: 8px`

**Betrag:**
- `font-size: 22px; font-weight: 600; letter-spacing: -0.5px`
- Leer-Zustand (Frei): `font-size: 20px; color: var(--text2)` → zeigt `—`

**Meta-Zeile:**
- `border-top: 1px solid var(--brd); padding-top: 10px`
- Trennpunkt zwischen Zeit und Positionen: `width 5px, height 5px, border-radius 50%, background: var(--brd)`

### Status-Badge

```
[● Besetzt]
```

- `display: inline-flex; align-items: center; gap: 4px`
- `font-size: 10px; font-weight: 600`
- `padding: 3px 8px; border-radius: 20px`
- Dot: `width 5px, height 5px, border-radius 50%, background: currentColor`
- `white-space: nowrap; flex-shrink: 0`

### Nav-Item (Sidebar)

- Standard: `font-size 12px, font-weight 500, color var(--text2), padding 7px 16px`
- Aktiv: `color var(--acc-t), background var(--acc-bg), font-weight 600`
- Section-Header: `9px uppercase letter-spacing 0.8px, padding 14px 16px 4px`
- Trennlinie: `height 1px, background var(--brd), margin 4px 0`

### Zone-Pills (Tab-Filter)

- `font-size 11px; font-weight 600; padding 5px 13px`
- `border-radius: 20px; border: 1px solid var(--brd)`
- Inaktiv: transparent, `color var(--text2)`
- Aktiv: `background var(--acc); color #fff; border-color var(--acc)`

### Schnellkasse-Banner

- `background: var(--acc); border-radius: 13px; padding: 13px 16px`
- `margin: 0 16px 16px`
- Layout: `display flex; justify-content space-between; align-items center`
- Pfeil-Box: `width 28px; height 28px; border-radius 8px; background rgba(255,255,255,0.18); color white`

### Session-Chip (Topbar)

- `background var(--acc-bg); color var(--acc-t)`
- `font-size 11px; font-weight 600; padding 4px 10px; border-radius 20px`

### KPI-Block (Sidebar unten)

- Label: `9px uppercase letter-spacing 0.6px, color var(--text2)`
- Wert: `18px font-weight 600, color var(--text)`
- Highlight-Wert (Umsatz): `color var(--acc)`
- Abstand zwischen KPIs: `margin-bottom 10px`

### Dark-Mode-Toggle

- `width 38px; height 22px; border-radius 11px`
- Light: `background var(--sur2)`
- Dark: `background var(--acc-bg)`
- Knopf: `16px × 16px, border-radius 50%`
  - Light: `background var(--text2), left 2px`
  - Dark: `background var(--acc), transform translateX(16px)`

---

## 5. Brand-Mark (Topbar Logo)

- Größe: `26px × 26px; border-radius 8px; background var(--acc)`
- Icon: 4-Quadrat-Grid, `fill white`, 11px × 11px

---

## 6. Borders & Radius — Zusammenfassung

| Element | Radius | Border |
|---|---|---|
| App-Shell | 18px | — |
| Tischkachel | 14px | 1px solid var(--brd) |
| Schnellkasse-Banner | 13px | — |
| Badge | 20px (pill) | — |
| Zone-Pill | 20px (pill) | 1px solid var(--brd) |
| Brand-Mark | 8px | — |
| Toggle-Knopf-Box | 8px | — |
| Pfeil-Box | 8px | — |
| Toggle | 11px | 1px solid var(--brd) |

---

## 7. Vollständige Screen-Liste

Abgeleitet aus der Nav-Struktur der Sidebar. Alle Screens teilen dieselbe Shell (Topbar + Sidebar), nur der Content-Bereich rechts wechselt.

### Sidebar-Struktur (fix, alle Screens)

```
── Übersicht ──────────────────
  Tische            ✅ fertig
  Produkte
  Kategorien

── Abrechnung ─────────────────
  Kassensitzung
  Berichte
  Z-Bericht

── System ─────────────────────
  Einstellungen
```

### Screens nach Priorität

#### Gruppe 1 — Kern-Kassen-Flow (höchste Priorität)

| # | Screen | Aufruf | Inhalt |
|---|---|---|---|
| 1 | **SchnellkasseView** | Schnellkasse-Banner | Direkteinstieg ohne Tisch — gleicher Flow wie OrderView, aber ohne Tischauswahl |
| 2 | **OrderView** | Tisch antippen | Produktgitter (nach Kategorien) + Warenkorb-Sidebar rechts |
| 3 | **ModifierSheet** | Produkt antippen (Modal) | Pflicht- und Optionalauswahl, Aufpreis live, "Hinzufügen"-Button |
| 4 | **PaymentView** | "Bezahlen" in OrderView | MwSt-Aufschlüsselung, Bar/Karte/Gemischt, Split-Option |
| 5 | **ReceiptView** | Nach erfolgreicher Zahlung | Digitaler Bon, alle Pflichtfelder, QR-Code (TSE), "PDF senden" |

#### Gruppe 2 — Verwaltung Übersicht

| # | Screen | Nav-Punkt | Inhalt |
|---|---|---|---|
| 6 | **ProdukteView** | Übersicht → Produkte | Liste aller Produkte, Preis, MwSt, Kategorie, aktiv/inaktiv |
| 7 | **KategorienView** | Übersicht → Kategorien | Kategorien verwalten, Farbe, Sortierung |

#### Gruppe 3 — Abrechnung

| # | Screen | Nav-Punkt | Inhalt |
|---|---|---|---|
| 8 | **KassensitzungView** | Abrechnung → Kassensitzung | Sitzung öffnen/schließen, Anfangs- und Endbestand, Einlagen/Entnahmen |
| 9 | **BerichteView** | Abrechnung → Berichte | Tagesübersicht, Umsatz nach Kategorie, Zahlungsarten |
| 10 | **ZBerichtView** | Abrechnung → Z-Bericht | Read-only Snapshot, alle Pflichtfelder, PDF-Export |

#### Gruppe 4 — System

| # | Screen | Nav-Punkt | Inhalt |
|---|---|---|---|
| 11 | **EinstellungenView** | System → Einstellungen | Betriebsdaten, Benutzerverwaltung, Geräteverwaltung, Abo-Info |

### Empfohlene Bau-Reihenfolge

```
0. LoginView          — ✅ fertig (abgenommen)
1. SchnellkasseView   — einfachster Einstieg, baut auf Tischübersicht auf
2. OrderView          — Herzstück der App
3. ModifierSheet      — Modal, direkt an OrderView gebunden
4. PaymentView        — Abschluss des Bestellflows
5. ReceiptView        — letzter Schritt im Flow
6. KassensitzungView  — Pflicht vor Go-live (GoBD)
7. ZBerichtView       — Pflicht vor Go-live (GoBD)
8. BerichteView
9. ProdukteView
10. KategorienView
11. EinstellungenView
```

---

## 8. LoginView — Spezifikation

### Layout

2-Spalten-Grid, `grid-template-columns: 1fr 400px`

**Linke Spalte (Brand-Fläche):**
- Hintergrund: `var(--acc)` / Dark: `#0d1a42`
- Padding: `36px`
- Inhalt von oben nach unten: Brand-Mark + Name → Headline + Subtext + Feature-Liste → Footer-Zeile
- Headline: `26px, font-weight 600, color white, letter-spacing -0.5px`
- Subtext: `12px, color rgba(255,255,255,0.55), line-height 1.65`
- Feature-Zeilen: Icon-Box `18×18px, border-radius 5px, background rgba(255,255,255,0.12)` + Text `12px, rgba(255,255,255,0.65)`
- Footer: `10px, rgba(255,255,255,0.3)`

**Rechte Spalte (Formular):**
- Hintergrund: `var(--sur)`
- Padding: `44px 36px 36px`
- Dark-Mode-Toggle oben rechts
- Titel `19px font-weight 600`, Subtitle `12px var(--text2)`
- Formular-Felder: `height 40px, border-radius 9px, background var(--bg), border 1px solid var(--inp-brd)`
- Focus-State: `border-color var(--acc)`
- Passwort-Feld: Auge-Icon rechts `14×14px, stroke var(--text2)`
- "Passwort vergessen?" — `11px, color var(--acc), float right`
- Submit-Button: `height 42px, border-radius 9px, background var(--acc), font-size 13px font-weight 600`

### PIN-Benutzerauswahl (unter Trennlinie)

Listenformat — **keine Kacheln**:

```
┌──────────────────────────────────────┐
│  [N]  Niko              Owner    ›   │
├──────────────────────────────────────┤
│  [S]  Sara              Staff    ›   │
├──────────────────────────────────────┤
│  [M]  Mehmet            Manager  ›   │
└──────────────────────────────────────┘
```

- Zeile: `padding 9px 12px, border-radius 10px, border 1px solid var(--brd), background var(--bg)`
- Hover: `border-color var(--acc), background var(--acc-bg)`
- Avatar: `30×30px, border-radius 50%`
  - Owner/erster User: `background var(--acc-bg), color var(--acc-t)`
  - Weitere User: `background var(--sur2), color var(--text2)`
- Name: `12px font-weight 600, color var(--text)`
- Rolle: `10px, color var(--text2)`
- Pfeil: `13×13px, stroke var(--text2)`

### Trennlinie (E-Mail-Login ↔ PIN)

- `display flex, align-items center, gap 10px`
- Linie: `height 1px, background var(--brd), flex 1`
- Text: `10px, color var(--text2)` — "oder mit PIN wechseln"

### Versions-Footer

- `10px, color var(--text2), text-align center, margin-top 20px`
- Inhalt: `v1.0.0 · Keine Schicht offen`

---

*Design System v1.2 — LoginView ergänzt*  
*Font: Plus Jakarta Sans | Akzent: Electric Blue #1a6fff | Basis: Stone/Off-White*

// E-Mail-Palette = die „Ledger Green"-Tokens aus DesignSystem.swift (DS.C) als HEX.
// Grund für die Kopie: E-Mail-Clients können weder Asset-Kataloge noch adaptive
// Farben. Die Werte sind exakt die Light-Variante der `Color.adaptive(light:dark:)`
// Paare — plus die Dark-Werte separat, weil `prefers-color-scheme` in Apple Mail
// und iOS Mail (dem Gerät des Wirts!) zuverlässig greift.
export const mail = {
  light: {
    bg: '#F4F6F1',        // DS.C.bg    — Seitenhintergrund
    sur: '#FFFFFF',       // DS.C.sur   — Inhaltskarte
    sur2: '#ECEFE6',      // DS.C.sur2  — Panel, Footer
    brd: '#DDE2D4',       // DS.C.brdAdaptive
    text: '#1A1F17',      // DS.C.text
    text2: '#596052',     // DS.C.text2 — Sekundärtext
    acc: '#4A7310',       // DS.C.acc   — Buttonfläche (weiße Schrift)
    accBg: '#EDF3DE',     // DS.C.accBg — Tint-Fläche
    accT: '#3C5E0C',      // DS.C.accT  — Text/Links in Akzentfarbe
    brandPanel: '#1C2413', // DS.C.brandPanel — Header
    brandLeaf: '#AECB6E',  // DS.C.brandLeaf  — Wortmarken-Akzent
    brass: '#9A6A0B',     // DS.C.brass
    brassBg: '#F8F0DC',   // DS.C.brassBg — Warnfläche
    brassText: '#7C5507', // DS.C.brassText
    danger: '#BC3A2B',    // DS.C.danger
    dangerBg: '#FAECE9',
    dangerText: '#9E2F22',
    onAcc: '#FFFFFF',
    onBrand: '#F1F3EC',
    onBrandMuted: '#A2AA95',
  },
  dark: {
    bg: '#121410',
    sur: '#1B1E17',
    sur2: '#262A20',
    brd: '#31362B',
    text: '#F1F3EC',
    text2: '#A2AA95',
    acc: '#6D9A28',
    accBg: '#232B15',
    accT: '#AECB6E',
    brandPanel: '#141A0D',
    brandLeaf: '#AECB6E',
    brass: '#D9AC46',
    brassBg: '#2C240E',
    brassText: '#E2BE67',
    danger: '#E1745F',
    dangerBg: '#371711',
    dangerText: '#EE9C86',
    onAcc: '#FFFFFF',
    onBrand: '#F1F3EC',
    onBrandMuted: '#A2AA95',
  },
} as const;

// System-Stack (OFFEN.md §5) — keine Webfonts: die App nutzt seit Design v3.1
// ohnehin System-Schrift, und Webfonts laden in Mail-Clients nur unzuverlässig.
export const fontBody =
  "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

// Geldbeträge tabellarisch: gleiche Ziffernbreite = Beträge fluchten untereinander
// (Pendant zu `.dsFont(.money…)` mit Tabellenziffern im Frontend).
export const fontMono =
  "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace";

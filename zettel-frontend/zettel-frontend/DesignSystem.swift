// DesignSystem.swift
// cashbox — Design Tokens v3.0 „Ledger Green"
//
// Signatur: ruhige Präzision einer Registrierkasse. Tiefes Olivgrün als
// Geldfarbe, Messing (Brass) für angeforderte Zahlungen, olivgetönte
// Neutrals. SF Pro trägt die UI, Geldbeträge laufen in SF Rounded mit
// Tabellenziffern (.monospacedDigit) — Beträge in Listen fluchten,
// Timer zittern nicht.
//
// Farbstrategie: Restrained — Grün nur für primäre Aktionen, Auswahl
// und Geld-Zustände; Brass nur für "Zahlung offen"; Rot nur für Storno
// und Fehler. Alles andere bleibt neutral.

import SwiftUI
import UIKit

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Design System Namespace

enum DS {

    // MARK: Colors
    enum C {
        // Canvas & Flächen — olivgetönte Neutrals (kein Blaugrau)
        static let bg   = Color.adaptive(light: "F4F6F1", dark: "121410")
        static let sur  = Color.adaptive(light: "FFFFFF", dark: "1B1E17")
        static let sur2 = Color.adaptive(light: "ECEFE6", dark: "262A20")

        // Text
        static let text  = Color.adaptive(light: "1A1F17", dark: "F1F3EC")
        static let text2 = Color.adaptive(light: "596052", dark: "A2AA95")

        // Borders — Ink mit niedriger Deckkraft, passt sich beiden Modi an
        static let brdLight = Color(hex: "1A1F17").opacity(0.10)
        static let brdDark  = Color(hex: "F1F3EC").opacity(0.10)

        static func brd(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? brdDark : brdLight
        }
        /// Scheme-unabhängige Border (für Kontexte ohne colorScheme-Zugriff)
        static let brdAdaptive = Color.adaptive(light: "DDE2D4", dark: "31362B")

        // Primär — Ledger Green (Geld, Aktionen, Auswahl)
        static let acc   = Color.adaptive(light: "4A7310", dark: "6D9A28")   // Füllungen (weiße Schrift)
        static let accBg = Color.adaptive(light: "EDF3DE", dark: "232B15")   // Tint-Flächen
        static let accT  = Color.adaptive(light: "3C5E0C", dark: "AECB6E")   // Text/Icons in Akzentfarbe
        static let accPressed = Color.adaptive(light: "3C5E0C", dark: "587F1D")

        // Brand-Panel (Login/Onboarding linke Spalte) — tiefes Nacht-Olive
        static let brandPanel = Color.adaptive(light: "1C2413", dark: "141A0D")

        // Sekundär — Brass (Zahlung angefordert, Hinweise, Trial)
        static let brass     = Color.adaptive(light: "9A6A0B", dark: "D9AC46")
        static let brassBg   = Color.adaptive(light: "F8F0DC", dark: "2C240E")
        static let brassText = Color.adaptive(light: "7C5507", dark: "E2BE67")

        // Semantik — Erfolg (nutzt die Ledger-Green-Familie)
        static let successBg   = accBg
        static let successText = accT

        // Semantik — Gefahr (Storno, Fehler, Löschungen)
        static let danger     = Color.adaptive(light: "BC3A2B", dark: "E1745F")
        static let dangerBg   = Color.adaptive(light: "FAECE9", dark: "371711")
        static let dangerText = Color.adaptive(light: "9E2F22", dark: "EE9C86")

        // Semantik — Warnung (TSE instabil etc.) → Brass-Familie
        static let warnBg   = brassBg
        static let warnText = brassText

        // Tisch-Status
        // frei    = ruhig/neutral (Default-Zustand schreit nicht)
        // besetzt = Ledger Green (Geld liegt auf dem Tisch)
        // zahlung = Brass (Aufmerksamkeit: Gast wartet)
        static let freeBg   = sur2
        static let freeText = text2
        static let busyBg   = accBg
        static let busyText = accT
        static let billBg   = brassBg
        static let billText = brassText
    }

    // MARK: Typographie — feste Skala, iPad auf Armlänge
    // SF Pro (System). Geldbeträge über DS.F.money* (SF Rounded, Tabellenziffern).
    enum F {
        /// Sehr große Beträge: Tischkacheln, KPI-Kacheln
        static func moneyDisplay(_ size: CGFloat = 40) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        /// Beträge in Zeilen, Footern, Buttons
        static func money(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static let display  = Font.system(size: 40, weight: .bold)      // Screen-KPIs
        static let title    = Font.system(size: 26, weight: .bold)      // Seitentitel
        static let heading  = Font.system(size: 20, weight: .semibold)  // Kartentitel, Tischname
        static let body     = Font.system(size: 17, weight: .regular)   // Standardtext
        static let bodyMed  = Font.system(size: 17, weight: .medium)
        static let bodyBold = Font.system(size: 17, weight: .semibold)
        static let sub      = Font.system(size: 15, weight: .regular)   // Sekundärtext
        static let subMed   = Font.system(size: 15, weight: .medium)
        static let subBold  = Font.system(size: 15, weight: .semibold)
        static let caption  = Font.system(size: 13, weight: .medium)    // Meta, Badges
        static let captionBold = Font.system(size: 13, weight: .semibold)
        static let label    = Font.system(size: 12, weight: .semibold)  // Abschnitts-Label (versal)
    }

    // MARK: Typo-Größen (Alt-API — Views nutzen zunehmend DS.F)
    enum T {
        static let topbarAppName: CGFloat  = 18
        static let navItem: CGFloat        = 16
        static let sectionHeader: CGFloat  = 12
        static let sessionChip: CGFloat    = 14
        static let quickLabel: CGFloat     = 17
        static let quickSub: CGFloat       = 14
        static let kpiValue: CGFloat       = 32
        static let kpiLabel: CGFloat       = 12
        static let tableName: CGFloat      = 20
        static let tableAmount: CGFloat    = 40
        static let tableMeta: CGFloat      = 14
        static let badge: CGFloat          = 12
        static let zonePill: CGFloat       = 14
        static let loginHeadline: CGFloat  = 32
        static let loginTitle: CGFloat     = 20
        static let loginBody: CGFloat      = 15
        static let loginButton: CGFloat    = 16
        static let loginForgot: CGFloat    = 14
        static let loginFooter: CGFloat    = 12
        static let loginFeature: CGFloat   = 14
    }

    // MARK: Border Radii — ruhig, nicht überrundet
    enum R {
        static let appShell:    CGFloat = 16
        static let card:        CGFloat = 14
        static let quickBanner: CGFloat = 12
        static let badge:       CGFloat = 100   // Pill
        static let brandMark:   CGFloat = 9
        static let input:       CGFloat = 10
        static let button:      CGFloat = 10
        static let pinRow:      CGFloat = 12
        static let control:     CGFloat = 8
    }

    // MARK: Sizes & Spacing — Touch-first (44pt-Minimum ernst genommen)
    enum S {
        static let topbarHeight:    CGFloat = 60
        static let sidebarWidth:    CGFloat = 252
        static let formPanelWidth:  CGFloat = 420
        static let brandMarkSize:   CGFloat = 30
        static let inputHeight:     CGFloat = 50
        static let buttonHeight:    CGFloat = 52
        static let avatarSize:      CGFloat = 36
        static let featureIconSize: CGFloat = 20
        static let touchTarget:     CGFloat = 44
        static let qtyButton:       CGFloat = 38   // + umgebendes Padding ≥ 44pt Trefferfläche
        static let pagePad:         CGFloat = 24
        static let cardPad:         CGFloat = 20
    }

    // MARK: Motion — Zustand, nicht Dekoration
    enum M {
        static let fast  = Animation.easeOut(duration: 0.12)
        static let base  = Animation.easeOut(duration: 0.18)
        static let slow  = Animation.easeOut(duration: 0.25)
        static let press = Animation.easeOut(duration: 0.10)
    }
}

// MARK: - Geld-Formatierung (eine Quelle für die ganze App)

private let _euroFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.locale = Locale(identifier: "de_DE")
    return f
}()

/// Cent → "1.234,56 €"
func euroString(_ cents: Int) -> String {
    let val = NSNumber(value: Double(cents) / 100.0)
    return (_euroFormatter.string(from: val) ?? "0,00") + " €"
}

/// Geldbetrag mit Tabellenziffern — fluchtet in Listen, zittert nicht in Timern
struct MoneyText: View {
    let cents: Int
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    var color: Color = DS.C.text

    var body: some View {
        Text(euroString(cents))
            .font(DS.F.money(size, weight: weight))
            .monospacedDigit()
            .foregroundColor(color)
    }
}

// MARK: - Button Styles

/// Primäraktion: Ledger-Green-Füllung, weiße Schrift
struct DSPrimaryButton: ButtonStyle {
    var height: CGFloat = DS.S.buttonHeight
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .fill(configuration.isPressed ? DS.C.accPressed : DS.C.acc)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

/// Sekundäraktion: getönte Fläche, Ink-Schrift
struct DSSecondaryButton: ButtonStyle {
    var height: CGFloat = DS.S.buttonHeight
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(DS.C.text)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .fill(DS.C.sur2.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

/// Destruktive Aktion: rote Tint-Fläche
struct DSDestructiveButton: ButtonStyle {
    var height: CGFloat = DS.S.buttonHeight
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(DS.C.dangerText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                RoundedRectangle(cornerRadius: DS.R.button)
                    .fill(DS.C.dangerBg.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.M.press, value: configuration.isPressed)
    }
}

// MARK: - Card / Fläche

extension View {
    /// Standard-Karte: weiße Fläche, 14er-Radius, 1px-Hairline (kein Schatten)
    func dsCard(padding: CGFloat = DS.S.cardPad) -> some View {
        self
            .padding(padding)
            .background(DS.C.sur)
            .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
            )
    }

    /// Eingabefeld-Rahmen mit Fokus-Zustand
    func dsInput(focused: Bool = false) -> some View {
        self
            .padding(.horizontal, 14)
            .frame(height: DS.S.inputHeight)
            .background(DS.C.sur)
            .clipShape(RoundedRectangle(cornerRadius: DS.R.input))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(focused ? DS.C.acc : DS.C.brdAdaptive,
                                  lineWidth: focused ? 1.5 : 1)
            )
            .animation(DS.M.fast, value: focused)
    }
}

// MARK: - Status-Pill

struct DSPill: View {
    let label: String
    let fg: Color
    let bg: Color
    var showDot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showDot {
                Circle().fill(fg).frame(width: 7, height: 7)
            }
            Text(label)
                .font(DS.F.captionBold)
                .foregroundColor(fg)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(bg))
        .fixedSize()
    }
}

// MARK: - Abschnitts-Label (Sidebar, Formulare)

struct DSSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DS.F.label)
            .foregroundColor(DS.C.text2)
            .tracking(0.7)
    }
}

// MARK: - Empty State

struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.C.sur2)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DS.C.text2)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(DS.F.heading)
                    .foregroundColor(DS.C.text)
                Text(message)
                    .font(DS.F.sub)
                    .foregroundColor(DS.C.text2)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(DSPrimaryButton(height: 46, fullWidth: false))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Font-Shim (Alt-API)
// Plus Jakarta Sans wurde nie gebundelt — alle .jakarta()-Aufrufe fielen
// still auf das System-Font zurück. Der Shim macht das explizit: SF Pro.
// Neue/überarbeitete Views nutzen DS.F direkt.

extension Font {
    static func jakarta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

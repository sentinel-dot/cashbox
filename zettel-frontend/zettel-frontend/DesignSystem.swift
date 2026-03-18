// DesignSystem.swift
// cashbox — Design Tokens (kassensystem-design-system.md v1.2)
// Alle Farben, Schriftgrößen, Abstände zentral definiert.

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

    /// Erzeugt eine adaptive Farbe, die auf Light/Dark Mode reagiert.
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
        // Hintergründe
        static let bg      = Color.adaptive(light: "f5f4f1", dark: "13131a")
        static let sur     = Color.adaptive(light: "ffffff", dark: "1c1c26")
        static let sur2    = Color.adaptive(light: "eceae5", dark: "252535")

        // Text
        static let text    = Color.adaptive(light: "1a1a1f", dark: "eeeef8")
        static let text2   = Color.adaptive(light: "9a98a8", dark: "6a6888")

        // Borders — mit Opacity, scheme-abhängig
        static let brdLight = Color(hex: "1a1a1f").opacity(0.08)
        static let brdDark  = Color(hex: "eeeef8").opacity(0.07)

        static func brd(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? brdDark : brdLight
        }

        // Akzent — Electric Blue
        static let acc    = Color.adaptive(light: "1a6fff", dark: "4d8fff")
        static let accBg  = Color.adaptive(light: "e8f0ff", dark: "0d1f50")
        static let accT   = Color.adaptive(light: "0a3dbf", dark: "90bbff")

        // Brand-Panel Hintergrund (Login linke Spalte)
        static let brandPanel = Color.adaptive(light: "1a6fff", dark: "0d1a42")

        // Tisch-Status-Farben
        static let freeBg    = Color.adaptive(light: "e8f5ec", dark: "0d2818")
        static let freeText  = Color.adaptive(light: "1a5c30", dark: "60d080")
        static let busyBg    = Color.adaptive(light: "eef4ff", dark: "0d1a40")
        static let busyText  = Color.adaptive(light: "0a3dbf", dark: "90bbff")
        static let billBg    = Color.adaptive(light: "fff8e0", dark: "281e08")
        static let billText  = Color.adaptive(light: "8a6000", dark: "f0c060")

        // Akzent-Streifen (Tischkachel linker Rand)
        static let stripeBusy = Color(hex: "1a6fff")
        static let stripeBill = Color(hex: "d4a017")
    }

    // MARK: Typography
    enum T {
        static let topbarAppName: CGFloat  = 20
        static let navItem: CGFloat        = 19
        static let kpiValue: CGFloat       = 28
        static let kpiLabel: CGFloat       = 14
        static let tableName: CGFloat      = 21
        static let tableAmount: CGFloat    = 36
        static let tableMeta: CGFloat      = 15
        static let badge: CGFloat          = 13
        static let zonePill: CGFloat       = 15
        static let sessionChip: CGFloat    = 15
        static let quickLabel: CGFloat     = 18
        static let quickSub: CGFloat       = 14
        static let sectionHeader: CGFloat  = 13

        // Login-spezifisch
        static let loginHeadline: CGFloat  = 26
        static let loginTitle: CGFloat     = 19
        static let loginBody: CGFloat      = 12
        static let loginButton: CGFloat    = 13
        static let loginForgot: CGFloat    = 11
        static let loginFooter: CGFloat    = 10
        static let loginFeature: CGFloat   = 12
    }

    // MARK: Border Radii
    enum R {
        static let appShell: CGFloat     = 18
        static let card: CGFloat         = 14
        static let quickBanner: CGFloat  = 13
        static let badge: CGFloat        = 20  // pill
        static let brandMark: CGFloat    = 8
        static let input: CGFloat        = 9
        static let button: CGFloat       = 9
        static let pinRow: CGFloat       = 10
    }

    // MARK: Sizes & Spacing
    enum S {
        static let topbarHeight: CGFloat     = 58
        static let sidebarWidth: CGFloat     = 280
        static let formPanelWidth: CGFloat   = 400
        static let brandMarkSize: CGFloat    = 30
        static let inputHeight: CGFloat      = 40
        static let buttonHeight: CGFloat     = 42
        static let avatarSize: CGFloat       = 30
        static let featureIconSize: CGFloat  = 18
        static let touchTarget: CGFloat      = 44
    }
}

// MARK: - Font Helper (Plus Jakarta Sans)

extension Font {
    static func jakarta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:     name = "PlusJakartaSans-Medium"
        case .semibold:   name = "PlusJakartaSans-SemiBold"
        case .bold:       name = "PlusJakartaSans-Bold"
        case .heavy:      name = "PlusJakartaSans-ExtraBold"
        default:          name = "PlusJakartaSans-Regular"
        }
        return .custom(name, size: size)
    }
}

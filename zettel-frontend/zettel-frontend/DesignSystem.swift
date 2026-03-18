// DesignSystem.swift
// cashbox — Design Tokens v2.0 (iPad POS, Rich Indigo Accent)

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
        // Backgrounds — clean neutral
        static let bg   = Color.adaptive(light: "F9FAFB", dark: "111827")
        static let sur  = Color.adaptive(light: "FFFFFF", dark: "1F2937")
        static let sur2 = Color.adaptive(light: "F3F4F6", dark: "374151")

        // Text
        static let text  = Color.adaptive(light: "111827", dark: "F9FAFB")
        static let text2 = Color.adaptive(light: "6B7280", dark: "9CA3AF")

        // Borders
        static let brdLight = Color(hex: "111827").opacity(0.08)
        static let brdDark  = Color(hex: "F9FAFB").opacity(0.07)

        static func brd(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? brdDark : brdLight
        }

        // Accent — Rich Indigo (premium, cross-category)
        static let acc   = Color.adaptive(light: "4F46E5", dark: "818CF8")
        static let accBg = Color.adaptive(light: "EEF2FF", dark: "1E1B4B")
        static let accT  = Color.adaptive(light: "3730A3", dark: "A5B4FC")

        // Brand Panel (Login left column)
        static let brandPanel = Color.adaptive(light: "4338CA", dark: "1E1B4B")

        // Semantic — Success
        static let successBg   = Color.adaptive(light: "ECFDF5", dark: "064E3B")
        static let successText = Color.adaptive(light: "065F46", dark: "34D399")

        // Semantic — Danger
        static let danger     = Color.adaptive(light: "DC2626", dark: "EF4444")
        static let dangerBg   = Color.adaptive(light: "FEF2F2", dark: "450A0A")
        static let dangerText = Color.adaptive(light: "991B1B", dark: "FCA5A5")

        // Semantic — Warning
        static let warnBg   = Color.adaptive(light: "FFFBEB", dark: "27200A")
        static let warnText = Color.adaptive(light: "92400E", dark: "FCD34D")

        // Table Status
        static let freeBg   = Color.adaptive(light: "ECFDF5", dark: "064E3B")
        static let freeText = Color.adaptive(light: "065F46", dark: "34D399")
        static let busyBg   = Color.adaptive(light: "EFF6FF", dark: "1E3A5F")
        static let busyText = Color.adaptive(light: "1D4ED8", dark: "60A5FA")
        static let billBg   = Color.adaptive(light: "EEF2FF", dark: "1E1B4B")
        static let billText = Color.adaptive(light: "3730A3", dark: "A5B4FC")

        // Table Card Left Stripes
        static let stripeBusy = Color(hex: "2563EB")
        static let stripeBill = Color(hex: "4F46E5")
    }

    // MARK: Typography — iPad-optimized (readable at arm's length)
    enum T {
        // App shell
        static let topbarAppName: CGFloat  = 18
        static let navItem: CGFloat        = 15
        static let sectionHeader: CGFloat  = 11
        static let sessionChip: CGFloat    = 13
        static let quickLabel: CGFloat     = 16
        static let quickSub: CGFloat       = 13

        // KPIs / Data — large & scannable
        static let kpiValue: CGFloat       = 34
        static let kpiLabel: CGFloat       = 11
        static let tableName: CGFloat      = 18
        static let tableAmount: CGFloat    = 38
        static let tableMeta: CGFloat      = 13
        static let badge: CGFloat          = 11
        static let zonePill: CGFloat       = 13

        // Content — was "loginXxx", kept for compatibility but now iPad-sized
        static let loginHeadline: CGFloat  = 32
        static let loginTitle: CGFloat     = 20
        static let loginBody: CGFloat      = 15
        static let loginButton: CGFloat    = 15
        static let loginForgot: CGFloat    = 13
        static let loginFooter: CGFloat    = 12
        static let loginFeature: CGFloat   = 13
    }

    // MARK: Border Radii
    enum R {
        static let appShell:    CGFloat = 20
        static let card:        CGFloat = 16
        static let quickBanner: CGFloat = 14
        static let badge:       CGFloat = 20
        static let brandMark:   CGFloat = 10
        static let input:       CGFloat = 10
        static let button:      CGFloat = 10
        static let pinRow:      CGFloat = 12
    }

    // MARK: Sizes & Spacing — iPad POS optimized
    enum S {
        static let topbarHeight:    CGFloat = 64
        static let sidebarWidth:    CGFloat = 256
        static let formPanelWidth:  CGFloat = 420
        static let brandMarkSize:   CGFloat = 32
        static let inputHeight:     CGFloat = 48
        static let buttonHeight:    CGFloat = 50
        static let avatarSize:      CGFloat = 36
        static let featureIconSize: CGFloat = 20
        static let touchTarget:     CGFloat = 50
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

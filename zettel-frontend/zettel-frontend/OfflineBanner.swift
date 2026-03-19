// OfflineBanner.swift
// cashbox — System-Banner: Offline, TSE-Warnung, TSE-Ausfall, Sync-OK, Trial

import SwiftUI

// MARK: - Basis-Komponente

private struct AppBanner: View {
    let icon:       String          // SF Symbol
    let label:      String          // Fettgedruckt
    let message:    String          // Normaler Text dahinter
    let bg:         Color
    let fg:         Color
    let actionLabel: String?
    let actionFg:   Color
    let onAction:   (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(fg)
                .frame(width: 15)

            Group {
                Text(label).fontWeight(.semibold) + Text(" — ") + Text(message)
            }
            .font(.jakarta(12, weight: .regular))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(actionFg)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(bg)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Offline Banner

/// Wird überall im App als `OfflineBanner()` verwendet.
/// pendingCount > 0 zeigt die Anzahl ausstehender TSE-Signaturen.
struct OfflineBanner: View {
    var pendingCount: Int = 0

    private let bg  = Color(UIColor { _ in UIColor(red: 0.176, green: 0.176, blue: 0.176, alpha: 1) })
    private let fg  = Color(UIColor { _ in UIColor(red: 0.961, green: 0.957, blue: 0.945, alpha: 1) })
    private let amberFg = Color(UIColor { _ in UIColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) })

    var body: some View {
        AppBanner(
            icon:        "wifi.slash",
            label:       "Kein Netz",
            message:"TSE-Signierung ausstehend. Bestellungen lokal gespeichert.",
            bg:          bg,
            fg:          fg,
            actionLabel: pendingCount > 0 ? "\(pendingCount) ausstehend →" : nil,
            actionFg:    amberFg,
            onAction:    pendingCount > 0 ? {} : nil
        )
    }
}

// MARK: - TSE-Warnung Banner

struct TSEWarnBanner: View {
    var onDetails: (() -> Void)? = nil

    var body: some View {
        AppBanner(
            icon:        "exclamationmark.triangle",
            label:       "TSE instabil",
            message:"Fiskaly antwortet langsam. Bons werden verzögert signiert.",
            bg:          DS.C.warnBg,
            fg:          DS.C.warnText,
            actionLabel: onDetails != nil ? "Details" : nil,
            actionFg:    DS.C.warnText,
            onAction:    onDetails
        )
    }
}

// MARK: - TSE-Ausfall Banner

struct TSEErrorBanner: View {
    let hoursDown: Int
    var onReport:  (() -> Void)? = nil

    var body: some View {
        AppBanner(
            icon:        "xmark.circle",
            label:       "TSE-Ausfall seit \(hoursDown) Stunden",
            message:"Meldepflicht beim Finanzamt. Kasse weiter nutzbar.",
            bg:          DS.C.dangerBg,
            fg:          DS.C.dangerText,
            actionLabel: onReport != nil ? "Jetzt melden →" : nil,
            actionFg:    DS.C.dangerText,
            onAction:    onReport
        )
    }
}

// MARK: - Sync-OK Banner

struct SyncOKBanner: View {
    let count:      Int
    var onDismiss:  (() -> Void)? = nil

    var body: some View {
        AppBanner(
            icon:        "checkmark.circle",
            label:       "Sync erfolgreich",
            message:"\(count) ausstehende TSE-Signatur\(count == 1 ? "" : "en") erfolgreich synchronisiert.",
            bg:          DS.C.freeBg,
            fg:          DS.C.freeText,
            actionLabel: onDismiss != nil ? "Schließen" : nil,
            actionFg:    DS.C.freeText,
            onAction:    onDismiss
        )
    }
}

// MARK: - Trial-Warnung Banner

struct TrialBanner: View {
    let daysLeft:   Int
    var onUpgrade:  (() -> Void)? = nil

    var body: some View {
        AppBanner(
            icon:        "info.circle",
            label:       "Trial endet in \(daysLeft) Tag\(daysLeft == 1 ? "" : "en")",
            message:"Jetzt upgraden um unterbrechungsfreien Betrieb sicherzustellen.",
            bg:          DS.C.accBg,
            fg:          DS.C.accT,
            actionLabel: onUpgrade != nil ? "Jetzt upgraden →" : nil,
            actionFg:    DS.C.accT,
            onAction:    onUpgrade
        )
    }
}

// MARK: - Previews

#Preview("Alle Banner") {
    VStack(spacing: 0) {
        OfflineBanner(pendingCount: 3)
        OfflineBanner()
        TSEWarnBanner(onDetails: {})
        TSEErrorBanner(hoursDown: 52, onReport: {})
        SyncOKBanner(count: 3, onDismiss: {})
        TrialBanner(daysLeft: 2, onUpgrade: {})
        Spacer()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 0) {
        OfflineBanner(pendingCount: 3)
        TSEWarnBanner()
        TSEErrorBanner(hoursDown: 52)
        SyncOKBanner(count: 1)
        TrialBanner(daysLeft: 2)
        Spacer()
    }
    .preferredColorScheme(.dark)
}

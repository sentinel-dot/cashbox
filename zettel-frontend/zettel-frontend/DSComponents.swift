// DSComponents.swift
// cashbox — Design-System-Komponenten v3.1
//
// Baut auf den Tokens in DesignSystem.swift auf und ergänzt:
//   1. dsFont(_:)          — Dynamic-Type-fähige Typo-Tokens (ersetzt DS.F-Statics)
//   2. DSTextField         — das eine Eingabefeld der App (ersetzt 11 Hand-Kopien)
//   3. DSSheetScaffold     — einheitliches Sheet-Chrome inkl. Dirty-Guard
//   4. DSSegmentedControl  — Segment-Auswahl im Ledger-Look (MwSt, Rollen, Zeitraum)
//   5. DSSkeleton          — Lade-Placeholder statt zentriertem Spinner
//   6. Haptics             — zentrale Haptik-Trigger (auf iPads meist No-Op,
//                            deshalb tragen Delight-Momente immer auch visuell)
//   7. DSAppearance        — System/Hell/Dunkel statt erzwungenem Toggle

import SwiftUI
import UIKit

// MARK: - 1. Dynamic-Type-fähige Typografie
//
// Font.system(size:) kennt kein relativeTo: — skalierende System-Fonts brauchen
// UIFontMetrics. Der Modifier liest die aktuelle DynamicTypeSize aus der
// Environment und skaliert die Basisgröße über den passenden TextStyle,
// dadurch aktualisiert er live bei Größenänderung.

enum DSText {
    case display, title, heading
    case body, bodyMed, bodyBold
    case sub, subMed, subBold
    case caption, captionBold
    case label
    /// Beträge in Zeilen, Footern, Buttons (SF Rounded, Tabellenziffern)
    case money(CGFloat = 17, weight: Font.Weight = .semibold)
    /// Sehr große Beträge: Tischkacheln, KPI-Kacheln
    case moneyDisplay(CGFloat = 40)
    /// SF-Symbol-Größen (Icons skalieren mit dem umgebenden Text)
    case icon(CGFloat, weight: Font.Weight = .medium)
    /// Rohe Sondergröße (skaliert) — für Layout-Spezialfälle außerhalb der Skala
    case raw(CGFloat, weight: Font.Weight = .regular)
    /// Monospace (Beleg-/Dokument-Ästhetik: Bon, Z-Bericht, IDs)
    case mono(CGFloat, weight: Font.Weight = .regular)

    var spec: (size: CGFloat, weight: Font.Weight, design: Font.Design, style: UIFont.TextStyle, monoDigits: Bool) {
        switch self {
        case .display:                 return (40, .bold,     .default, .largeTitle,  false)
        case .title:                   return (26, .bold,     .default, .title1,      false)
        case .heading:                 return (20, .semibold, .default, .title3,      false)
        case .body:                    return (17, .regular,  .default, .body,        false)
        case .bodyMed:                 return (17, .medium,   .default, .body,        false)
        case .bodyBold:                return (17, .semibold, .default, .body,        false)
        case .sub:                     return (15, .regular,  .default, .subheadline, false)
        case .subMed:                  return (15, .medium,   .default, .subheadline, false)
        case .subBold:                 return (15, .semibold, .default, .subheadline, false)
        case .caption:                 return (13, .medium,   .default, .footnote,    false)
        case .captionBold:             return (13, .semibold, .default, .footnote,    false)
        case .label:                   return (12, .semibold, .default, .caption1,    false)
        case .money(let s, let w):     return (s,  w,         .rounded, s >= 28 ? .largeTitle : .body, true)
        case .moneyDisplay(let s):     return (s,  .bold,     .rounded, .largeTitle,  true)
        case .icon(let s, let w), .raw(let s, let w):
            let style: UIFont.TextStyle = s <= 14 ? .footnote : (s <= 17 ? .body : .title3)
            return (s, w, .default, style, false)
        case .mono(let s, let w):
            let style: UIFont.TextStyle = s <= 14 ? .footnote : (s <= 17 ? .body : .title3)
            return (s, w, .monospaced, style, false)
        }
    }
}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall:         return .extraSmall
        case .small:          return .small
        case .medium:         return .medium
        case .large:          return .large
        case .xLarge:         return .extraLarge
        case .xxLarge:        return .extraExtraLarge
        case .xxxLarge:       return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default:     return .large
        }
    }
}

private struct DSFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let token: DSText
    var monoDigits = false

    func body(content: Content) -> some View {
        let spec = token.spec
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.uiContentSizeCategory)
        let size = UIFontMetrics(forTextStyle: spec.style)
            .scaledValue(for: spec.size, compatibleWith: traits)
        let font = Font.system(size: size, weight: spec.weight, design: spec.design)
        return content.font((spec.monoDigits || monoDigits) ? font.monospacedDigit() : font)
    }
}

extension View {
    /// Dynamic-Type-fähiges Typo-Token — ersetzt `.font(DS.F.…)` und `.font(.system(size:…))`.
    /// `monoDigits: true` für Tabellenziffern außerhalb der money-Tokens (Timer, Zähler).
    func dsFont(_ token: DSText, monoDigits: Bool = false) -> some View {
        modifier(DSFontModifier(token: token, monoDigits: monoDigits))
    }
}

// MARK: - 2. DSTextField
//
// Das eine Eingabefeld der App. Engine ist NoAssistantTextField (verhindert die
// iPad-InputAssistant-Constraint-Konflikte, die SwiftUIs TextField auslöst),
// Hülle ist dsInput() — Fokus-Border inklusive. Fehlerzustand: rote Border +
// Meldung unter dem Feld.

struct DSTextField: View {
    var label: String? = nil
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: UITextAutocapitalizationType = .none
    var autocorrection: UITextAutocorrectionType = .no
    var alignment: NSTextAlignment = .natural
    var hint: String? = nil
    var errorText: String? = nil

    @State private var focused  = false
    @State private var revealed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = DS.S.inputHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                DSSectionLabel(text: label)
            }
            HStack(spacing: 8) {
                NoAssistantTextField(
                    placeholder:            placeholder,
                    text:                   $text,
                    keyboardType:           keyboard,
                    uiFont:                 scaledUIFont,
                    uiTextColor:            UIColor(DS.C.text),
                    textAlignment:          alignment,
                    isSecure:               isSecure && !revealed,
                    textContentType:        contentType,
                    autocapitalizationType: capitalization,
                    autocorrectionType:     autocorrection,
                    isFocused:              $focused
                )
                if isSecure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .dsFont(.icon(15))
                            .foregroundColor(DS.C.text2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Passwort verbergen" : "Passwort anzeigen")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: fieldHeight)
            .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.input)
                    .strokeBorder(
                        errorText != nil ? DS.C.danger : (focused ? DS.C.acc : DS.C.brdAdaptive),
                        lineWidth: (focused || errorText != nil) ? 1.5 : 1
                    )
            )
            .animation(DS.M.fast, value: focused)

            if let errorText {
                Text(errorText)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.dangerText)
            } else if let hint {
                Text(hint)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
        }
    }

    private var scaledUIFont: UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.uiContentSizeCategory)
        let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: 16, compatibleWith: traits)
        return UIFont.systemFont(ofSize: size)
    }
}

// MARK: - 3. DSSheetScaffold
//
// Einheitliches Sheet-Chrome (kanonisch nach dem Produkte-Sheet): Icon-Badge +
// Titel/Untertitel + Schließen-Kreis, darunter scrollender Inhalt, optionaler
// Footer. `isDirty` blockiert Swipe-Dismiss und fragt beim Schließen nach.

struct DSSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var isDirty: Bool = false
    /// false → Aufrufer verwaltet Scrolling selbst (z.B. Sheets mit eigener Tab-Bar)
    var scrolls: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView(showsIndicators: false) {
                    content()
                        .padding(20)
                }
            } else {
                content()
            }
            footerBar
        }
        .background(DS.C.sur)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Änderungen verwerfen?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Verwerfen", role: .destructive) { dismiss() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Deine Eingaben gehen verloren.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.C.accBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .dsFont(.icon(16, weight: .semibold))
                        .foregroundColor(DS.C.accT)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
                if let subtitle {
                    Text(subtitle)
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
            }
            Spacer()
            Button {
                if isDirty {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .dsFont(.icon(13, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.C.sur2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schließen")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }

    @ViewBuilder
    private var footerBar: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 0) {
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                footer()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
    }
}

extension DSSheetScaffold where Footer == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isDirty: Bool = false,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title, subtitle: subtitle, icon: icon,
            isDirty: isDirty, scrolls: scrolls,
            content: content, footer: { EmptyView() }
        )
    }
}

// MARK: - 4. DSSegmentedControl
//
// Segment-Auswahl im Ledger-Look (nativer .segmented lässt sich nicht auf die
// Tokens stylen). Thumb gleitet per matchedGeometryEffect, Reduce Motion
// schaltet auf sofortigen Wechsel.

struct DSSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    @Namespace private var thumbNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var segmentHeight: CGFloat = 38

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                Button {
                    if reduceMotion {
                        selection = option.value
                    } else {
                        withAnimation(DS.M.base) { selection = option.value }
                    }
                    Haptics.selection()
                } label: {
                    Text(option.label)
                        .dsFont(selection == option.value ? .subBold : .subMed)
                        .foregroundColor(selection == option.value ? DS.C.accT : DS.C.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: DS.R.control)
                                    .fill(DS.C.sur)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.R.control)
                                            .strokeBorder(DS.C.brdAdaptive, lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "thumb", in: thumbNS)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: DS.R.control))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: DS.R.control + 3).fill(DS.C.sur2))
    }
}

// MARK: - 5. DSSkeleton
//
// Lade-Placeholder: sur2-Fläche mit wanderndem Schimmer. Screens komponieren
// daraus Layouts, die dem echten Inhalt entsprechen (Kacheln, Zeilen, KPIs),
// statt einen Spinner in die Mitte zu stellen. Bei Reduce Motion statisch.

struct DSSkeleton: View {
    var height: CGFloat
    var cornerRadius: CGFloat = DS.R.control
    var width: CGFloat? = nil

    @State private var phase: CGFloat = -0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(DS.C.sur2)
            .overlay(
                LinearGradient(
                    colors: [.clear, DS.C.sur.opacity(0.7), .clear],
                    startPoint: UnitPoint(x: phase, y: 0.4),
                    endPoint: UnitPoint(x: phase + 0.6, y: 0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

// MARK: - Erfolgs-Checkmark (Peak-Moment)
//
// Zeichnender Haken für Erfolgs-Momente (Zahlung abgeschlossen, Kasse stimmt).
// Bei Reduce Motion erscheint er sofort. Haptik triggert der Aufrufer
// (Haptics.success()) — auf iPads ohne Taptic Engine trägt die Animation.

struct DSSuccessCheckmark: View {
    var size: CGFloat = 72
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.C.accBg)
                .frame(width: size, height: size)
                .scaleEffect(drawn ? 1 : 0.85)
            DSCheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(DS.C.accT, style: StrokeStyle(
                    lineWidth: max(3, size * 0.075), lineCap: .round, lineJoin: .round
                ))
                .frame(width: size * 0.40, height: size * 0.30)
        }
        .onAppear {
            if reduceMotion {
                drawn = true
            } else {
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) { drawn = true }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DSCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.width * 0.36, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        return p
    }
}

// MARK: - Banner-Transition (Reduce-Motion-sicher)
//
// Statt an jeder Banner-Einfügestelle .move(edge:.top) zu wiederholen:
// ein Modifier, der bei Reduce Motion auf Crossfade umschaltet.

private struct DSBannerTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(
            reduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
        )
    }
}

extension View {
    /// Einfüge-Transition für Banner (OfflineBanner etc.) — Crossfade bei Reduce Motion
    func dsBannerTransition() -> some View {
        modifier(DSBannerTransition())
    }
}

// MARK: - 6. Haptics
//
// Zentrale Haptik-Trigger. Auf den meisten iPads ohne Taptic Engine ein No-Op —
// Delight-Momente müssen deshalb immer auch visuell tragen.

enum Haptics {
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap()       { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - 7. DSAppearance
//
// System/Hell/Dunkel statt erzwungenem Hell/Dunkel-Toggle. Default: System —
// die App folgt der iPadOS-Einstellung; der Override bleibt für Betriebe, die
// z.B. im dunklen Laden dauerhaft Dark wollen.

enum DSAppearance: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }
}

// MARK: - Previews

#Preview("DSTextField") {
    struct Demo: View {
        @State var name = ""
        @State var pw = ""
        var body: some View {
            VStack(spacing: 20) {
                DSTextField(label: "Name", placeholder: "z.B. Doppel-Apfel", text: $name)
                DSTextField(label: "Passwort", placeholder: "••••••", text: $pw, isSecure: true)
                DSTextField(placeholder: "email@betrieb.de", text: .constant("kaputt@"),
                            keyboard: .emailAddress, errorText: "Bitte gib eine gültige E-Mail-Adresse ein.")
            }
            .padding(32)
            .background(DS.C.bg)
        }
    }
    return Demo()
}

#Preview("DSSheetScaffold") {
    DSSheetScaffold(
        title: "Neues Produkt",
        subtitle: "Produkt anlegen",
        icon: "plus",
        isDirty: true
    ) {
        VStack(spacing: 16) {
            DSTextField(label: "Name", placeholder: "Produktname", text: .constant(""))
        }
    } footer: {
        HStack(spacing: 12) {
            Button("Abbrechen") {}.buttonStyle(DSSecondaryButton())
            Button("Speichern") {}.buttonStyle(DSPrimaryButton())
        }
    }
}

#Preview("DSSegmentedControl + Skeleton") {
    struct Demo: View {
        @State var vat = "19"
        var body: some View {
            VStack(spacing: 28) {
                DSSegmentedControl(selection: $vat, options: [
                    (value: "7", label: "7 % ermäßigt"),
                    (value: "19", label: "19 % regulär"),
                ])
                VStack(spacing: 10) {
                    DSSkeleton(height: 92, cornerRadius: DS.R.card)
                    DSSkeleton(height: 92, cornerRadius: DS.R.card)
                    DSSkeleton(height: 20, width: 180)
                }
            }
            .padding(32)
            .background(DS.C.bg)
        }
    }
    return Demo()
}

// KassensitzungView.swift
// cashbox — Kassensitzung: Schicht öffnen, Bewegungen, Abschluss + Z-Bericht
// Design v3: zentrale Geld-Formatierung (euroString), Touch-Formulare,
// destruktiver Abschluss klar als solcher gekennzeichnet.

import SwiftUI

// MARK: - Root

struct KassensitzungView: View {
    @EnvironmentObject var sessionStore:   SessionStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var showCloseSheet    = false
    @State private var showMovementSheet = false
    @State private var zReport:          CloseSessionResult?
    @State private var showZReport       = false
    @State private var error:            AppError?
    @State private var showError         = false
    // Live gezählter Kasseninhalt (KassenstandCard) — hier gehalten, damit er
    // das Abschluss-Sheet vorbefüllt („wird bei Abschluss gespeichert").
    @State private var countedCashText   = ""

    // Pre-fill für Abschluss-Modal
    private var expectedCash: Int {
        guard let s = sessionStore.currentSession else { return 0 }
        let dep = s.movements.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountCents }
        let wit = s.movements.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountCents }
        return s.openingCashCents + dep - wit
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner().dsBannerTransition()
                }
                if sessionStore.isLoading && sessionStore.currentSession == nil {
                    Spacer(); ProgressView().progressViewStyle(.circular).scaleEffect(1.2); Spacer()
                } else if sessionStore.hasOpenSession {
                    ActiveSessionView(
                        showCloseSheet:    $showCloseSheet,
                        showMovementSheet: $showMovementSheet,
                        countedCashText:   $countedCashText
                    )
                } else {
                    NoSessionView()
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .animation(DS.M.slow, value: sessionStore.hasOpenSession)
        .task { await sessionStore.loadCurrent() }
        .sheet(isPresented: $showCloseSheet) {
            CloseSessionSheet(expectedCents: expectedCash, prefillText: countedCashText) { closingCents in
                await performClose(closingCents: closingCents)
            }
        }
        .sheet(isPresented: $showMovementSheet) {
            AddMovementSheet { type, amountCents, reason in
                await performAddMovement(type: type, amountCents: amountCents, reason: reason)
            }
        }
        .sheet(isPresented: $showZReport) {
            if let report = zReport { ZReportSummarySheet(result: report) }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    private func performClose(closingCents: Int) async {
        do {
            zReport = try await sessionStore.close(closingCashCents: closingCents)
            showZReport = true
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func performAddMovement(type: MovementType, amountCents: Int, reason: String) async {
        do {
            try await sessionStore.addMovement(type: type, amountCents: amountCents, reason: reason)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }
}

// MARK: - Aktive Session (offene Schicht)

private struct ActiveSessionView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var showCloseSheet:    Bool
    @Binding var showMovementSheet: Bool
    @Binding var countedCashText:   String

    var body: some View {
        guard let session = sessionStore.currentSession else { return AnyView(EmptyView()) }

        let depositTotal    = session.movements.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountCents }
        let withdrawalTotal = session.movements.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountCents }
        let expectedCash    = session.openingCashCents + depositTotal - withdrawalTotal

        return AnyView(
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ActivePageHeader(session: session, onClose: { showCloseSheet = true })

                    VStack(alignment: .leading, spacing: 16) {
                        // KPI-Reihe — „Erwarteter Kassenstand" lebt kanonisch in der
                        // Kassenstand-Karte darunter (dort wird gezählt), nicht doppelt hier
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                            spacing: 12
                        ) {
                            KPICard(
                                label: "Eröffnungsbestand",
                                cents: session.openingCashCents,
                                sub:   "manuell gezählt"
                            )
                            KPICard(
                                label: "Einlagen",
                                cents: depositTotal,
                                sub:   "\(session.movements.filter { $0.type == .deposit }.count) Einlagen",
                                prefix: "+"
                            )
                            KPICard(
                                label: "Entnahmen",
                                cents: withdrawalTotal,
                                sub:   "\(session.movements.filter { $0.type == .withdrawal }.count) Entnahmen",
                                prefix: withdrawalTotal > 0 ? "−" : nil
                            )
                        }

                        // Haupt-Spalten
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                KassenstandCard(
                                    openingCents:    session.openingCashCents,
                                    depositTotal:    depositTotal,
                                    withdrawalTotal: withdrawalTotal,
                                    expectedCash:    expectedCash,
                                    currentCashText: $countedCashText
                                )
                                EinlagenCard(
                                    movements: session.movements,
                                    onAdd:     { showMovementSheet = true }
                                )
                            }

                            VStack(spacing: 16) {
                                ZahlungsartenCard(session: session)
                                SessionInfoCard(session: session)
                            }
                            .frame(width: 340)
                        }
                    }
                    .padding(.horizontal, DS.S.pagePad)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        )
    }
}

// MARK: - Page Header

private struct ActivePageHeader: View {
    let session: CashRegisterSession
    let onClose: () -> Void
    @EnvironmentObject var sessionStore: SessionStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Kassensitzung")
                        .dsFont(.title)
                        .foregroundColor(DS.C.text)
                    DSPill(
                        label: "Offen seit \(formatTimeOnly(session.openedAt))",
                        fg: DS.C.accT,
                        bg: DS.C.accBg
                    )
                }
                Text("Geöffnet von \(session.openedByName)")
                    .dsFont(.sub)
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "lock")
                        .dsFont(.raw(14, weight: .semibold))
                    Text("Schicht abschließen")
                }
            }
            .buttonStyle(DSDestructiveButton(height: 46, fullWidth: false))
            .disabled(sessionStore.isLoading)
        }
        .padding(.horizontal, DS.S.pagePad)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let label:  String
    let cents:  Int
    let sub:    String
    var prefix: String? = nil
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSSectionLabel(text: label)
            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix)
                        .dsFont(.money(24, weight: .bold))
                        .foregroundColor(accent ? DS.C.accT : DS.C.text)
                }
                MoneyText(cents: cents, size: 24, weight: .bold,
                          color: accent ? DS.C.accT : DS.C.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(sub)
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 16)
    }
}

// MARK: - Kassenstand Card

private struct KassenstandCard: View {
    let openingCents:    Int
    let depositTotal:    Int
    let withdrawalTotal: Int
    let expectedCash:    Int

    // Live-Eingabe Kasseninhalt — State liegt in KassensitzungView und
    // befüllt von dort das Abschluss-Sheet vor
    @Binding var currentCashText: String
    @State private var inputFocused = false

    private var currentCents: Int? {
        let c = currentCashText.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(c), v >= 0 else { return nil }
        return Int((v * 100).rounded())
    }

    private var differenceCents: Int {
        guard let c = currentCents else { return 0 }
        return c - expectedCash
    }

    private var diffColor: Color {
        guard currentCents != nil else { return DS.C.text }
        return differenceCents >= 0 ? DS.C.accT : DS.C.dangerText
    }

    var body: some View {
        SecCard {
            SecCardHead(title: "Kassenstand", sub: "Anfangsbestand + Einlagen − Entnahmen")

            HStack(spacing: 0) {
                KsCel(label: "Anfangsbestand",     value: euroString(openingCents), sub: "manuell gezählt", color: DS.C.text)
                Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)
                KsCel(label: "Erwarteter Bestand", value: euroString(expectedCash), sub: "berechnet",       color: DS.C.text)
                Rectangle().fill(DS.C.brdAdaptive).frame(width: 1)
                KsCel(
                    label: "Differenz",
                    value: currentCents == nil ? "—" : (differenceCents >= 0 ? "+ \(euroString(abs(differenceCents)))" : "− \(euroString(abs(differenceCents)))"),
                    sub:   currentCents == nil ? "nach Eingabe" : (differenceCents == 0 ? "Soll = Ist" : "Differenz"),
                    color: diffColor
                )
            }
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)

            // Input-Zeile
            HStack(spacing: 12) {
                Text("Aktueller Kasseninhalt:")
                    .dsFont(.subMed)
                    .foregroundColor(DS.C.text2)
                    .fixedSize()
                HStack(spacing: 8) {
                    NoAssistantTextField(
                        placeholder:  "0,00",
                        text:         $currentCashText,
                        keyboardType: .decimalPad,
                        uiFont:       UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold),
                        uiTextColor:  UIColor(DS.C.text),
                        isFocused:    $inputFocused
                    )
                    Text("€")
                        .dsFont(.sub)
                        .foregroundColor(DS.C.text2)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: 180)
                .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.bg))
                .overlay(RoundedRectangle(cornerRadius: DS.R.control).strokeBorder(inputFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: inputFocused ? 1.5 : 1))
                .animation(DS.M.fast, value: inputFocused)

                Text("wird bei Abschluss gespeichert")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
    }
}

private struct KsCel: View {
    let label: String
    let value: String
    let sub:   String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            DSSectionLabel(text: label)
            Text(value)
                .dsFont(.money(20, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .dsFont(.caption)
                .foregroundColor(DS.C.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Einlagen & Entnahmen Card

private struct EinlagenCard: View {
    let movements: [CashMovement]
    let onAdd:     () -> Void

    var body: some View {
        SecCard {
            SecCardHead(title: "Einlagen & Entnahmen", sub: "Kassenbewegungen dieser Schicht") {
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .dsFont(.raw(12, weight: .bold))
                        Text("Hinzufügen")
                            .dsFont(.captionBold)
                    }
                    .foregroundColor(DS.C.accT)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(DS.C.accBg))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if movements.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
                            .dsFont(.raw(22, weight: .medium))
                            .foregroundColor(DS.C.text2)
                        Text("Keine Bewegungen")
                            .dsFont(.sub)
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
            } else {
                // Lazy — Bewegungslisten wachsen über eine Schicht beliebig
                LazyVStack(spacing: 0) {
                    ForEach(Array(movements.enumerated()), id: \.offset) { idx, movement in
                        MovementRow(movement: movement)
                        if idx < movements.count - 1 {
                            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                                .padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }
}

private struct MovementRow: View {
    let movement: CashMovement
    private var isDeposit: Bool { movement.type == .deposit }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDeposit ? DS.C.accBg : DS.C.brassBg)
                    .frame(width: 34, height: 34)
                Image(systemName: isDeposit ? "arrow.up" : "arrow.down")
                    .dsFont(.raw(13, weight: .semibold))
                    .foregroundColor(isDeposit ? DS.C.accT : DS.C.brassText)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(movement.reason)
                    .dsFont(.subMed)
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)
                Text(movement.type.displayName)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            Text("\(isDeposit ? "+" : "−") \(euroString(movement.amountCents))")
                .dsFont(.money(15, weight: .semibold))
                .foregroundColor(isDeposit ? DS.C.accT : DS.C.brassText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Kassenbestand Card (rechts)

private struct ZahlungsartenCard: View {
    let session: CashRegisterSession

    private var depositTotal: Int {
        session.movements.filter { $0.type == .deposit }.reduce(0) { $0 + $1.amountCents }
    }
    private var withdrawalTotal: Int {
        session.movements.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        SecCard {
            SecCardHead(title: "Kassenbestand")

            PaymentRow(
                icon:   "banknote",
                label:  "Anfangsbestand",
                value:  euroString(session.openingCashCents),
                count:  "manuell"
            )
            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
            PaymentRow(
                icon:   "arrow.up.circle",
                label:  "Einlagen",
                value:  "+ \(euroString(depositTotal))",
                count:  "\(session.movements.filter { $0.type == .deposit }.count) Einlagen"
            )
            Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
            PaymentRow(
                icon:   "arrow.down.circle",
                label:  "Entnahmen",
                value:  "− \(euroString(withdrawalTotal))",
                count:  "\(session.movements.filter { $0.type == .withdrawal }.count) Entnahmen"
            )
            // Kein „Erwarteter Bestand" hier — kanonische Stelle ist die Kassenstand-Karte
        }
    }
}

private struct PaymentRow: View {
    let icon:  String
    let label: String
    let value: String
    let count: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .dsFont(.raw(15, weight: .medium))
                .foregroundColor(DS.C.text2)
                .frame(width: 24)
            Text(label)
                .dsFont(.subMed)
                .foregroundColor(DS.C.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .dsFont(.money(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text(count)
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Session Info Card (rechts unten)

private struct SessionInfoCard: View {
    let session: CashRegisterSession

    var body: some View {
        SecCard {
            SecCardHead(title: "Sitzungsdetails")
            VStack(spacing: 0) {
                InfoRow(label: "Status",        value: "Offen")
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                InfoRow(label: "Geöffnet von",  value: session.openedByName)
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                InfoRow(label: "Uhrzeit",       value: formatTimeOnly(session.openedAt))
                Rectangle().fill(DS.C.brdAdaptive).frame(height: 1)
                InfoRow(label: "Bewegungen",    value: "\(session.movements.count)")
            }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .dsFont(.sub)
                .foregroundColor(DS.C.text2)
            Spacer()
            Text(value)
                .dsFont(.subBold, monoDigits: true)
                .foregroundColor(DS.C.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Section Card Helpers

private struct SecCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(DS.C.sur)
        .clipShape(RoundedRectangle(cornerRadius: DS.R.card))
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
    }
}

private struct SecCardHead<Trailing: View>: View {
    let title: String
    var sub:   String?
    @ViewBuilder var trailing: Trailing

    init(title: String, sub: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title    = title
        self.sub      = sub
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dsFont(.bodyBold)
                    .foregroundColor(DS.C.text)
                if let s = sub {
                    Text(s)
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

// MARK: - Keine offene Session

private struct NoSessionView: View {
    @EnvironmentObject var sessionStore: SessionStore

    @State private var openingCashText = ""
    @State private var isLoading       = false
    @State private var error:          AppError?
    @State private var showError       = false
    @State private var fieldFocused    = false

    private var openingCents: Int? { parseCents(openingCashText) }
    private var canOpen: Bool { openingCents != nil && !isLoading }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(DS.C.accBg)
                        .frame(width: 60, height: 60)
                    Image(systemName: "building.columns")
                        .dsFont(.raw(24, weight: .semibold))
                        .foregroundColor(DS.C.accT)
                }
                Spacer().frame(height: 20)
                Text("Kasse öffnen")
                    .dsFont(.title)
                    .foregroundColor(DS.C.text)
                Spacer().frame(height: 6)
                Text("Zähle den aktuellen Bargeldbestand und gib ihn ein, um die Schicht zu starten.")
                    .dsFont(.sub)
                    .foregroundColor(DS.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 28)
                DSSectionLabel(text: "Kassenbestand (€)")
                Spacer().frame(height: 8)
                HStack(spacing: 8) {
                    NoAssistantTextField(
                        placeholder:   "0,00",
                        text:          $openingCashText,
                        keyboardType:  .decimalPad,
                        uiFont:        UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
                        uiTextColor:   UIColor(DS.C.text),
                        textAlignment: .right,
                        isFocused:     $fieldFocused
                    )
                    Text("€")
                        .dsFont(.heading)
                        .foregroundColor(DS.C.text2)
                }
                .padding(.horizontal, 16).frame(height: 60)
                .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.R.input)
                        .strokeBorder(fieldFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: fieldFocused ? 1.5 : 1)
                )
                .animation(DS.M.fast, value: fieldFocused)
                Spacer().frame(height: 10)
                if let cents = openingCents {
                    Text("= \(euroString(cents))")
                        .dsFont(.sub, monoDigits: true)
                        .foregroundColor(DS.C.text2).transition(.opacity)
                }
                Spacer().frame(height: 24)
                Button {
                    Task { await performOpen() }
                } label: {
                    Group {
                        if isLoading { ProgressView().progressViewStyle(.circular).tint(.white) }
                        else {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open")
                                    .dsFont(.raw(15, weight: .semibold))
                                Text("Kasse öffnen")
                            }
                        }
                    }
                }
                .buttonStyle(DSPrimaryButton())
                .disabled(!canOpen)
                .animation(DS.M.fast, value: canOpen)
            }
            .frame(width: 440)
            .dsCard(padding: 36)
            .alert("Fehler", isPresented: $showError) {
                Button("OK") { error = nil }
            } message: { Text(error?.localizedDescription ?? "Unbekannter Fehler") }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fieldFocused = true }
        }
    }

    private func performOpen() async {
        guard let cents = openingCents else { return }
        isLoading = true
        defer { isLoading = false }
        do { try await sessionStore.open(openingCashCents: cents) }
        catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }
}

// MARK: - Schicht abschließen Modal

private struct CloseSessionSheet: View {
    let expectedCents: Int
    var prefillText:   String = ""
    let onClose:       (Int) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var closingCashText = ""
    @State private var noteText        = ""
    @State private var isLoading       = false
    @State private var cashFocused     = false

    private var closingCents: Int? { parseCents(closingCashText) }
    private var differenceCents: Int { (closingCents ?? 0) - expectedCents }
    private var canClose: Bool { closingCents != nil && !isLoading }

    private var diffText: String {
        guard let c = closingCents else { return "" }
        let d = c - expectedCents
        let sign = d >= 0 ? "+" : "−"
        return "\(sign) \(euroString(abs(d)))"
    }

    private var diffSubtext: String {
        guard closingCents != nil else { return "" }
        return differenceCents == 0 ? "Kasse stimmt" : (differenceCents > 0 ? "Überschuss" : "Fehlbetrag")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Schicht abschließen", onClose: { dismiss() })

            VStack(alignment: .leading, spacing: 18) {
                // Kassenbestand gezählt
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Kassenbestand (gezählt)")
                    HStack(spacing: 8) {
                        NoAssistantTextField(
                            placeholder:   "0,00",
                            text:          $closingCashText,
                            keyboardType:  .decimalPad,
                            uiFont:        UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                            uiTextColor:   UIColor(DS.C.text),
                            isFocused:     $cashFocused
                        )
                        Text("€")
                            .dsFont(.sub)
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 14).frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(cashFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: cashFocused ? 1.5 : 1))
                    .animation(DS.M.fast, value: cashFocused)
                }

                // Soll/Ist/Differenz (nur wenn Betrag eingegeben)
                if closingCents != nil {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Erwarteter Bestand")
                                .dsFont(.sub).foregroundColor(DS.C.text2)
                            Spacer()
                            Text(euroString(expectedCents))
                                .dsFont(.money(15, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        HStack {
                            Text("Gezählt")
                                .dsFont(.sub).foregroundColor(DS.C.text2)
                            Spacer()
                            Text(euroString(closingCents ?? 0))
                                .dsFont(.money(15, weight: .semibold))
                                .foregroundColor(DS.C.text)
                        }
                        Divider()
                        HStack {
                            Text("Differenz — \(diffSubtext)")
                                .dsFont(.subBold)
                                .foregroundColor(differenceCents >= 0 ? DS.C.accT : DS.C.dangerText)
                            Spacer()
                            Text(diffText)
                                .dsFont(.money(16, weight: .bold))
                                .foregroundColor(differenceCents >= 0 ? DS.C.accT : DS.C.dangerText)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(
                        differenceCents >= 0 ? DS.C.accBg : DS.C.dangerBg
                    ))
                    .transition(.opacity)
                }

                // Anmerkung (optional)
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Anmerkung (optional)")
                    NoAssistantTextField(
                        placeholder: "z.B. Kasse ok, alles normal",
                        text:        $noteText,
                        uiFont:      UIFont.systemFont(ofSize: 15),
                        uiTextColor: UIColor(DS.C.text)
                    )
                    .padding(.horizontal, 14).frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                }
            }
            .padding(20)
            .animation(DS.M.base, value: closingCents != nil)

            // Footer
            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))
                Spacer()
                Button {
                    guard let cents = closingCents else { return }
                    isLoading = true
                    Task {
                        await onClose(cents)
                        isLoading = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if isLoading { ProgressView().progressViewStyle(.circular).tint(.white) }
                        else { Text("Abschließen & Z-Bericht") }
                    }
                    .dsFont(.raw(16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: DS.R.button).fill(DS.C.danger))
                    .opacity(canClose ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canClose)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // Dateneingabe — kein versehentliches Weg-Wischen (Abbrechen ist der Ausweg)
        .interactiveDismissDisabled(!closingCashText.isEmpty)
        .onAppear {
            // Live gezählter Kasseninhalt aus der KassenstandCard — keine Doppelzählung
            if closingCashText.isEmpty { closingCashText = prefillText }
            cashFocused = true
        }
    }
}

// MARK: - Kassenbewegung Modal

private struct AddMovementSheet: View {
    let onAdd: (MovementType, Int, String) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType:  MovementType = .deposit
    @State private var amountText     = ""
    @State private var reason         = ""
    @State private var isLoading      = false
    @State private var amountFocused  = false

    private var amountCents: Int? { parseCents(amountText) }
    private var canAdd: Bool {
        amountCents != nil && amountCents! > 0
        && !reason.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Kassenbewegung", onClose: { dismiss() })

            VStack(alignment: .leading, spacing: 18) {
                // Typ
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Typ")
                    DSSegmentedControl(selection: $selectedType, options: [
                        (value: MovementType.deposit,    label: MovementType.deposit.displayName),
                        (value: MovementType.withdrawal, label: MovementType.withdrawal.displayName),
                    ])
                }

                // Betrag
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Betrag (€)")
                    HStack(spacing: 8) {
                        NoAssistantTextField(
                            placeholder:   "0,00",
                            text:          $amountText,
                            keyboardType:  .decimalPad,
                            uiFont:        UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                            uiTextColor:   UIColor(DS.C.text),
                            isFocused:     $amountFocused
                        )
                        Text("€")
                            .dsFont(.sub)
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 14).frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(amountFocused ? DS.C.acc : DS.C.brdAdaptive, lineWidth: amountFocused ? 1.5 : 1))
                    .animation(DS.M.fast, value: amountFocused)
                }

                // Grund
                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Grund (Pflichtfeld)")
                    NoAssistantTextField(
                        placeholder: "z.B. Wechselgeld einlegen",
                        text:        $reason,
                        uiFont:      UIFont.systemFont(ofSize: 15),
                        uiTextColor: UIColor(DS.C.text)
                    )
                    .padding(.horizontal, 14).frame(height: DS.S.inputHeight)
                    .background(RoundedRectangle(cornerRadius: DS.R.input).fill(DS.C.bg))
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                }
            }
            .padding(20)

            // Footer
            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))
                Spacer()
                Button {
                    guard let cents = amountCents else { return }
                    isLoading = true
                    Task {
                        await onAdd(selectedType, cents, reason.trimmingCharacters(in: .whitespaces))
                        isLoading = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if isLoading { ProgressView().progressViewStyle(.circular).tint(.white) }
                        else { Text("Speichern") }
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!canAdd)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // Dateneingabe — kein versehentliches Weg-Wischen
        .interactiveDismissDisabled(!amountText.isEmpty || !reason.isEmpty)
        .onAppear { amountFocused = true }
    }
}

// MARK: - Sheet Header (gemeinsam)

private struct SheetHeader: View {
    let title:   String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .dsFont(.heading)
                .foregroundColor(DS.C.text)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .dsFont(.raw(13, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.C.sur2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

// MARK: - Z-Bericht Summary Sheet

private struct ZReportSummarySheet: View {
    let result: CloseSessionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Z-Bericht", onClose: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        DSSuccessCheckmark(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.differenceCents == 0 ? "Kasse stimmt" : "Kasse geschlossen")
                                .dsFont(.heading).foregroundColor(DS.C.text)
                            Text(result.differenceCents == 0
                                 ? "± 0,00 € · Z-Bericht #\(result.zReportId)"
                                 : "Z-Bericht #\(result.zReportId)")
                                .dsFont(.sub, monoDigits: true)
                                .foregroundColor(result.differenceCents == 0 ? DS.C.accT : DS.C.text2)
                        }
                    }
                    .onAppear { Haptics.success() }

                    VStack(spacing: 0) {
                        ZReportRow(label: "Umsatz gesamt",   value: euroString(result.totalRevenueCents), bold: true)
                        ZReportRow(label: "Bestellungen",    value: "\(result.totalOrders)")
                        ZReportRow(label: "Rabatte",         value: "− \(euroString(result.totalDiscountCents))")
                        ZReportRow(label: "Stornos",         value: "\(result.cancellationCount)")
                        Divider().padding(.vertical, 8)
                        ZReportRow(label: "Soll-Bestand",    value: euroString(result.expectedCashCents))
                        ZReportRow(label: "Ist-Bestand",     value: euroString(result.closingCashCents))
                        ZReportRow(
                            label:      "Differenz",
                            value:      (result.differenceCents >= 0 ? "+ " : "− ") + euroString(abs(result.differenceCents)),
                            valueColor: result.differenceCents == 0 ? DS.C.text : (result.differenceCents > 0 ? DS.C.accT : DS.C.dangerText),
                            bold:       true
                        )
                    }

                    Button("Fertig") { dismiss() }
                        .buttonStyle(DSPrimaryButton())
                }
                .padding(20)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

private struct ZReportRow: View {
    let label: String; let value: String
    var valueColor: Color = DS.C.text; var bold: Bool = false
    var body: some View {
        HStack {
            Text(label).dsFont(.sub).foregroundColor(DS.C.text2)
            Spacer()
            Text(value)
                .dsFont(.money(15, weight: bold ? .bold : .medium))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Helpers

// parseCents: zentral in DesignSystem.swift

private func formatTimeOnly(_ iso: String) -> String {
    guard iso.count >= 16 else { return iso }
    let s = iso.index(iso.startIndex, offsetBy: 11)
    let e = iso.index(iso.startIndex, offsetBy: 16)
    return "\(iso[s..<e]) Uhr"
}

// MARK: - Previews

#Preview("Keine Session") {
    KassensitzungView()
        .environmentObject(SessionStore.previewNoSession)
        .environmentObject(NetworkMonitor.preview)
}
#Preview("Aktive Session") {
    KassensitzungView()
        .environmentObject(SessionStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
#Preview("Dark Mode") {
    KassensitzungView()
        .environmentObject(SessionStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

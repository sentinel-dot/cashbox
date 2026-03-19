// KassensitzungView.swift
// cashbox — Kassensitzung: offene Schicht nach Referenz-Design

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
                    OfflineBanner().transition(.move(edge: .top).combined(with: .opacity))
                }
                if sessionStore.isLoading && sessionStore.currentSession == nil {
                    Spacer(); ProgressView().progressViewStyle(.circular).scaleEffect(1.2); Spacer()
                } else if sessionStore.hasOpenSession {
                    ActiveSessionView(
                        showCloseSheet:    $showCloseSheet,
                        showMovementSheet: $showMovementSheet
                    )
                } else {
                    NoSessionView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .animation(.easeInOut(duration: 0.25), value: sessionStore.hasOpenSession)
        .task { await sessionStore.loadCurrent() }
        .sheet(isPresented: $showCloseSheet) {
            CloseSessionSheet(expectedCents: expectedCash) { closingCents in
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

    var body: some View {
        guard let session = sessionStore.currentSession else { return AnyView(EmptyView()) }

        let depositTotal    = session.movements.filter { $0.type == .deposit    }.reduce(0) { $0 + $1.amountCents }
        let withdrawalTotal = session.movements.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountCents }
        let expectedCash    = session.openingCashCents + depositTotal - withdrawalTotal

        return AnyView(
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Page Header ────────────────────────────────────────
                    ActivePageHeader(session: session, onClose: { showCloseSheet = true })

                    VStack(alignment: .leading, spacing: 16) {
                        // ── KPI-Reihe ──────────────────────────────────────
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                            spacing: 12
                        ) {
                            KPICard(
                                label: "Eröffnungsbestand",
                                value: formatCents(session.openingCashCents),
                                sub:   "manuell gezählt",
                                accent: false
                            )
                            KPICard(
                                label: "Einlagen",
                                value: "+ \(formatCents(depositTotal))",
                                sub:   "\(session.movements.filter { $0.type == .deposit }.count) Einlagen",
                                accent: false
                            )
                            KPICard(
                                label: "Entnahmen",
                                value: withdrawalTotal > 0 ? "− \(formatCents(withdrawalTotal))" : "0,00 €",
                                sub:   "\(session.movements.filter { $0.type == .withdrawal }.count) Entnahmen",
                                accent: false
                            )
                            KPICard(
                                label: "Erwarteter Kassenstand",
                                value: formatCents(expectedCash),
                                sub:   "berechnet",
                                accent: true
                            )
                        }

                        // ── Haupt-Spalten ──────────────────────────────────
                        HStack(alignment: .top, spacing: 16) {

                            // Linke Spalte
                            VStack(spacing: 16) {
                                KassenstandCard(
                                    openingCents:    session.openingCashCents,
                                    depositTotal:    depositTotal,
                                    withdrawalTotal: withdrawalTotal,
                                    expectedCash:    expectedCash
                                )
                                EinlagenCard(
                                    movements: session.movements,
                                    onAdd:     { showMovementSheet = true }
                                )
                            }

                            // Rechte Spalte (320 px)
                            VStack(spacing: 16) {
                                ZahlungsartenCard(session: session)
                                SessionInfoCard(session: session)
                            }
                            .frame(width: 320)
                        }
                    }
                    .padding(.horizontal, 24)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Kassensitzung")
                        .font(.jakarta(18, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .tracking(-0.3)
                    // "Offen seit HH:MM" Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(DS.C.freeText)
                            .frame(width: 6, height: 6)
                        Text("Offen seit \(formatTimeOnly(session.openedAt))")
                            .font(.jakarta(10, weight: .semibold))
                            .foregroundColor(DS.C.freeText)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(DS.C.freeBg)
                    .cornerRadius(20)
                }
                Text("Geöffnet von \(session.openedByName)")
                    .font(.jakarta(12, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "minus.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Schicht abschließen")
                        .font(.jakarta(12, weight: .semibold))
                }
                .foregroundColor(DS.C.dangerText)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(DS.C.dangerBg)
                .cornerRadius(DS.R.button)
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isLoading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let label:  String
    let value:  String
    let sub:    String
    let accent: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold)).kerning(0.6)
                .foregroundColor(DS.C.text2)
            Text(value)
                .font(.jakarta(20, weight: .semibold))
                .foregroundColor(accent ? DS.C.acc : DS.C.text)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.jakarta(10, weight: .regular))
                .foregroundColor(DS.C.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.C.sur)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

// MARK: - Kassenstand Card

private struct KassenstandCard: View {
    let openingCents:    Int
    let depositTotal:    Int
    let withdrawalTotal: Int
    let expectedCash:    Int

    // Live-Eingabe Kasseninhalt (pre-fills close modal)
    @State private var currentCashText = ""
    @State private var inputFocused    = false
    @Environment(\.colorScheme) private var colorScheme

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
        return differenceCents == 0 ? DS.C.freeText : (differenceCents > 0 ? DS.C.freeText : DS.C.dangerText)
    }

    var body: some View {
        SecCard {
            // Header
            SecCardHead(title: "Kassenstand", sub: "Anfangsbestand + Einlagen − Entnahmen")

            // 3-Spalten Grid
            HStack(spacing: 0) {
                KsCel(label: "Anfangsbestand",     value: formatCents(openingCents),   sub: "manuell gezählt", color: DS.C.text)
                Rectangle().fill(DS.C.brdLight).frame(width: 1)
                KsCel(label: "Erwarteter Bestand", value: formatCents(expectedCash),   sub: "berechnet",       color: DS.C.text)
                Rectangle().fill(DS.C.brdLight).frame(width: 1)
                KsCel(
                    label: "Differenz",
                    value: currentCents == nil ? "—" : (differenceCents >= 0 ? "+ \(formatCents(abs(differenceCents)))" : "− \(formatCents(abs(differenceCents)))"),
                    sub:   currentCents == nil ? "nach Eingabe" : (differenceCents == 0 ? "Soll = Ist" : "Differenz"),
                    color: diffColor
                )
            }
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)

            // Input-Zeile
            HStack(spacing: 10) {
                Text("Aktueller Kasseninhalt:")
                    .font(.jakarta(12, weight: .medium))
                    .foregroundColor(DS.C.text2)
                    .fixedSize()
                NoAssistantTextField(
                    placeholder:  "0,00",
                    text:         $currentCashText,
                    keyboardType: .decimalPad,
                    uiFont:       UIFont.systemFont(ofSize: 13),
                    uiTextColor:  UIColor(DS.C.text),
                    isFocused:    $inputFocused
                )
                .padding(.horizontal, 12)
                .frame(height: 34)
                .frame(maxWidth: 160)
                .background(DS.C.bg)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(inputFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
                .animation(.easeInOut(duration: 0.15), value: inputFocused)

                Text("€ — wird bei Abschluss gespeichert")
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
    }
}

private struct KsCel: View {
    let label: String
    let value: String
    let sub:   String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold)).kerning(0.6)
                .foregroundColor(DS.C.text2)
            Text(value)
                .font(.jakarta(18, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.jakarta(10, weight: .regular))
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
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Hinzufügen")
                            .font(.jakarta(11, weight: .semibold))
                    }
                    .foregroundColor(DS.C.accT)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(DS.C.accBg)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }

            if movements.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(DS.C.text2)
                        Text("Keine Bewegungen")
                            .font(.jakarta(12, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(movements.enumerated()), id: \.offset) { idx, movement in
                        MovementRow(movement: movement)
                        if idx < movements.count - 1 {
                            Rectangle().fill(DS.C.brdLight).frame(height: 1)
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
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDeposit ? DS.C.freeBg : DS.C.warnBg)
                    .frame(width: 30, height: 30)
                Image(systemName: isDeposit ? "arrow.up" : "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDeposit ? DS.C.freeText : DS.C.warnText)
            }
            // Info
            VStack(alignment: .leading, spacing: 1) {
                Text(movement.reason)
                    .font(.jakarta(12, weight: .medium))
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)
                Text(movement.type.displayName)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            // Betrag
            Text("\(isDeposit ? "+" : "−") \(formatCents(movement.amountCents))")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(isDeposit ? DS.C.freeText : DS.C.warnText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Zahlungsarten Card (rechts)

private struct ZahlungsartenCard: View {
    let session: CashRegisterSession
    @Environment(\.colorScheme) private var colorScheme

    private var depositTotal: Int {
        session.movements.filter { $0.type == .deposit }.reduce(0) { $0 + $1.amountCents }
    }
    private var withdrawalTotal: Int {
        session.movements.filter { $0.type == .withdrawal }.reduce(0) { $0 + $1.amountCents }
    }
    private var expectedCash: Int { session.openingCashCents + depositTotal - withdrawalTotal }

    var body: some View {
        SecCard {
            SecCardHead(title: "Kassenbestand")

            // Zeilen
            PaymentRow(
                icon:   "banknote",
                label:  "Anfangsbestand",
                value:  formatCents(session.openingCashCents),
                count:  "manuell"
            )
            Rectangle().fill(DS.C.brdLight).frame(height: 1)
            PaymentRow(
                icon:   "arrow.up.circle",
                label:  "Einlagen",
                value:  "+ \(formatCents(depositTotal))",
                count:  "\(session.movements.filter { $0.type == .deposit }.count) Einlagen"
            )
            Rectangle().fill(DS.C.brdLight).frame(height: 1)
            PaymentRow(
                icon:   "arrow.down.circle",
                label:  "Entnahmen",
                value:  "− \(formatCents(withdrawalTotal))",
                count:  "\(session.movements.filter { $0.type == .withdrawal }.count) Entnahmen"
            )
            // Total row
            HStack {
                Text("Erwarteter Bestand")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Text(formatCents(expectedCash))
                    .font(.jakarta(16, weight: .semibold))
                    .foregroundColor(DS.C.acc)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
    }
}

private struct PaymentRow: View {
    let icon:  String
    let label: String
    let value: String
    let count: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(DS.C.sur2)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Text(label)
                .font(.jakarta(12, weight: .medium))
                .foregroundColor(DS.C.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text(count)
                    .font(.jakarta(10, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                InfoRow(label: "Geöffnet von",  value: session.openedByName)
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
                InfoRow(label: "Uhrzeit",       value: formatTimeOnly(session.openedAt))
                Rectangle().fill(DS.C.brdLight).frame(height: 1)
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
                .font(.jakarta(12, weight: .regular))
                .foregroundColor(DS.C.text2)
            Spacer()
            Text(value)
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(DS.C.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Section Card Helpers

private struct SecCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(DS.C.sur)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
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
        HStack(alignment: sub == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                if let s = sub {
                    Text(s)
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

// MARK: - Keine offene Session

private struct NoSessionView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.colorScheme) private var colorScheme

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
                    RoundedRectangle(cornerRadius: 14)
                        .fill(DS.C.accBg)
                        .frame(width: 56, height: 56)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                }
                Spacer().frame(height: 20)
                Text("Kasse öffnen")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer().frame(height: 4)
                Text("Geben Sie den aktuellen Kassenbestand ein, um die Kasse zu öffnen.")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 28)
                Text("KASSENBESTAND (€)")
                    .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                    .foregroundColor(DS.C.text2).tracking(0.5)
                Spacer().frame(height: 6)
                HStack(spacing: 8) {
                    NoAssistantTextField(
                        placeholder:   "0,00",
                        text:          $openingCashText,
                        keyboardType:  .decimalPad,
                        uiFont:        UIFont.systemFont(ofSize: 22, weight: .semibold),
                        uiTextColor:   UIColor(DS.C.text),
                        textAlignment: .right,
                        isFocused:     $fieldFocused
                    )
                    Text("€")
                        .font(.jakarta(18, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .padding(.horizontal, 16).frame(height: 56)
                .background(DS.C.bg).cornerRadius(DS.R.input)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.R.input)
                        .strokeBorder(fieldFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: fieldFocused ? 1.5 : 1)
                )
                .animation(.easeInOut(duration: 0.15), value: fieldFocused)
                Spacer().frame(height: 8)
                if let cents = openingCents {
                    Text("= \(formatCents(cents))")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2).transition(.opacity)
                }
                Spacer().frame(height: 24)
                Button { Task { await performOpen() } } label: {
                    Group {
                        if isLoading { ProgressView().progressViewStyle(.circular).tint(.white) }
                        else {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open.fill").font(.system(size: 14, weight: .semibold))
                                Text("Kasse öffnen").font(.jakarta(DS.T.loginButton, weight: .bold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                }
                .background(canOpen
                    ? LinearGradient(colors: [DS.C.acc, DS.C.acc.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [DS.C.acc.opacity(0.4), DS.C.acc.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(DS.R.button)
                .disabled(!canOpen)
                .animation(.easeInOut(duration: 0.15), value: canOpen)
            }
            .padding(36).frame(width: 440)
            .background(DS.C.sur).cornerRadius(DS.R.card)
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 8)
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
    let onClose:       (Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
        return "\(sign) \(formatCents(abs(d)))"
    }

    private var diffSubtext: String {
        guard let _ = closingCents else { return "" }
        return differenceCents == 0 ? "Kasse stimmt." : (differenceCents > 0 ? "Überschuss" : "Fehlbetrag")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schicht abschließen")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.C.brdLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Body
            VStack(alignment: .leading, spacing: 14) {
                // Kassenbestand gezählt
                VStack(alignment: .leading, spacing: 5) {
                    Text("KASSENBESTAND (GEZÄHLT)")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    HStack(spacing: 8) {
                        NoAssistantTextField(
                            placeholder:   "0,00",
                            text:          $closingCashText,
                            keyboardType:  .decimalPad,
                            uiFont:        UIFont.systemFont(ofSize: 16, weight: .semibold),
                            uiTextColor:   UIColor(DS.C.text),
                            isFocused:     $cashFocused
                        )
                        Text("€")
                            .font(.jakarta(14, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(DS.C.bg).cornerRadius(DS.R.input)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(cashFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
                    .animation(.easeInOut(duration: 0.15), value: cashFocused)
                }

                // Diff-Hinweis (nur wenn Betrag eingegeben)
                if let _ = closingCents {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Erwarteter Bestand: ")
                                .foregroundColor(DS.C.accT)
                            + Text(formatCents(expectedCents))
                                .bold().foregroundColor(DS.C.accT)
                            Text("  ·  Gezählt: ")
                                .foregroundColor(DS.C.accT)
                            + Text(formatCents(closingCents ?? 0))
                                .bold().foregroundColor(DS.C.accT)
                        }
                        .font(.jakarta(11, weight: .regular))
                        HStack {
                            Text("Differenz: ")
                                .foregroundColor(DS.C.accT)
                            + Text(diffText)
                                .bold().foregroundColor(DS.C.accT)
                            Text(" — \(diffSubtext)")
                                .foregroundColor(DS.C.accT)
                        }
                        .font(.jakarta(11, weight: .regular))
                    }
                    .padding(12)
                    .background(DS.C.accBg)
                    .cornerRadius(8)
                    .transition(.opacity)
                }

                // Anmerkung (optional)
                VStack(alignment: .leading, spacing: 5) {
                    Text("ANMERKUNG (OPTIONAL)")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder: "z.B. Kasse ok, alles normal",
                        text:        $noteText,
                        uiFont:      UIFont.systemFont(ofSize: 13),
                        uiTextColor: UIColor(DS.C.text)
                    )
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(DS.C.bg).cornerRadius(DS.R.input)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: closingCents != nil)

            // Footer
            HStack(spacing: 8) {
                Button("Abbrechen") { dismiss() }
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 16).frame(height: 38)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                    .buttonStyle(.plain)
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
                        else {
                            Text("Schicht abschließen & Z-Bericht")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                }
                .background(canClose ? DS.C.dangerText : DS.C.dangerText.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(!canClose)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { cashFocused = true }
    }
}

// MARK: - Kassenbewegung Modal

private struct AddMovementSheet: View {
    let onAdd: (MovementType, Int, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
            // Header
            HStack {
                Text("Kassenbewegung")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.C.brdLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Body
            VStack(alignment: .leading, spacing: 14) {
                // Typ
                VStack(alignment: .leading, spacing: 6) {
                    Text("TYP")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    HStack(spacing: 8) {
                        ForEach([MovementType.deposit, MovementType.withdrawal], id: \.self) { type in
                            let sel = selectedType == type
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) { selectedType = type }
                            } label: {
                                Text(type.displayName)
                                    .font(.jakarta(13, weight: .semibold))
                                    .foregroundColor(sel ? DS.C.acc : DS.C.text2)
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .background(sel ? DS.C.accBg : DS.C.sur2)
                                    .cornerRadius(DS.R.button)
                                    .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(sel ? DS.C.acc : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Betrag
                VStack(alignment: .leading, spacing: 5) {
                    Text("BETRAG (€)")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    HStack(spacing: 8) {
                        NoAssistantTextField(
                            placeholder:   "0,00",
                            text:          $amountText,
                            keyboardType:  .decimalPad,
                            uiFont:        UIFont.systemFont(ofSize: 16, weight: .semibold),
                            uiTextColor:   UIColor(DS.C.text),
                            isFocused:     $amountFocused
                        )
                        Text("€")
                            .font(.jakarta(14, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(DS.C.bg).cornerRadius(DS.R.input)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(amountFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1))
                    .animation(.easeInOut(duration: 0.15), value: amountFocused)
                }

                // Grund
                VStack(alignment: .leading, spacing: 5) {
                    Text("GRUND (PFLICHTFELD)")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder: "z.B. Wechselgeld einlegen",
                        text:        $reason,
                        uiFont:      UIFont.systemFont(ofSize: 13),
                        uiTextColor: UIColor(DS.C.text)
                    )
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(DS.C.bg).cornerRadius(DS.R.input)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.input).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                }
            }
            .padding(20)

            // Footer
            HStack(spacing: 8) {
                Button("Abbrechen") { dismiss() }
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 16).frame(height: 38)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                    .buttonStyle(.plain)
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
                        else {
                            Text("Speichern")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                }
                .background(canAdd ? DS.C.acc : DS.C.acc.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(!canAdd)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { amountFocused = true }
    }
}

// MARK: - Z-Bericht Summary Sheet (unverändert)

private struct ZReportSummarySheet: View {
    let result: CloseSessionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Z-Bericht")
                    .font(.jakarta(15, weight: .semibold)).foregroundColor(DS.C.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(DS.C.text2)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.C.brdLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(DS.C.freeBg).frame(width: 40, height: 40)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold)).foregroundColor(DS.C.freeText)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kasse geschlossen")
                                .font(.jakarta(DS.T.loginTitle, weight: .semibold)).foregroundColor(DS.C.text)
                            Text("Z-Bericht #\(result.zReportId)")
                                .font(.jakarta(DS.T.loginBody, weight: .regular)).foregroundColor(DS.C.text2)
                        }
                    }

                    VStack(spacing: 0) {
                        ZReportRow(label: "Umsatz gesamt",   value: formatCents(result.totalRevenueCents), bold: true)
                        ZReportRow(label: "Bestellungen",    value: "\(result.totalOrders)")
                        ZReportRow(label: "Rabatte",         value: "− \(formatCents(result.totalDiscountCents))")
                        ZReportRow(label: "Stornos",         value: "\(result.cancellationCount)")
                        Divider().padding(.vertical, 8)
                        ZReportRow(label: "Soll-Bestand",    value: formatCents(result.expectedCashCents))
                        ZReportRow(label: "Ist-Bestand",     value: formatCents(result.closingCashCents))
                        ZReportRow(
                            label:      "Differenz",
                            value:      (result.differenceCents >= 0 ? "+ " : "− ") + formatCents(abs(result.differenceCents)),
                            valueColor: result.differenceCents == 0 ? DS.C.text : (result.differenceCents > 0 ? DS.C.freeText : DS.C.dangerText),
                            bold:       true
                        )
                    }

                    Button { dismiss() } label: {
                        Text("Fertig").font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                    }
                    .background(DS.C.acc).cornerRadius(DS.R.button).buttonStyle(.plain)
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
            Text(label).font(.jakarta(DS.T.loginBody, weight: .regular)).foregroundColor(DS.C.text2)
            Spacer()
            Text(value).font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular)).foregroundColor(valueColor)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Helpers

private func parseCents(_ text: String) -> Int? {
    let n = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !n.isEmpty, let v = Double(n), v >= 0 else { return nil }
    return Int((v * 100).rounded())
}

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
}

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

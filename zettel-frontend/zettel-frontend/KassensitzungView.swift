// KassensitzungView.swift
// cashbox — Kassensitzung öffnen, schließen, Movements (Einlagen/Entnahmen)

import SwiftUI

// MARK: - Root View

struct KassensitzungView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @State private var showCloseSheet    = false
    @State private var showMovementSheet = false
    @State private var zReport: CloseSessionResult?
    @State private var showZReport       = false
    @State private var error: AppError?
    @State private var showError         = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if sessionStore.isLoading && sessionStore.currentSession == nil {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                    Spacer()
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
        // Session schließen
        .sheet(isPresented: $showCloseSheet) {
            CloseSessionSheet { closingCents in
                await performClose(closingCents: closingCents)
            }
        }
        // Movement hinzufügen
        .sheet(isPresented: $showMovementSheet) {
            AddMovementSheet { type, amountCents, reason in
                await performAddMovement(type: type, amountCents: amountCents, reason: reason)
            }
        }
        // Z-Bericht nach Abschluss
        .sheet(isPresented: $showZReport) {
            if let report = zReport {
                ZReportSummarySheet(result: report)
            }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────

    private func performClose(closingCents: Int) async {
        do {
            zReport = try await sessionStore.close(closingCashCents: closingCents)
            showZReport = true
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }

    private func performAddMovement(type: MovementType, amountCents: Int, reason: String) async {
        do {
            try await sessionStore.addMovement(type: type, amountCents: amountCents, reason: reason)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

// MARK: - Keine offene Session

private struct NoSessionView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var openingCashText = ""
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showError = false
    @FocusState private var fieldFocused: Bool

    private var openingCents: Int? {
        parseCents(openingCashText)
    }
    private var canOpen: Bool {
        openingCents != nil && !isLoading
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.C.accBg)
                        .frame(width: 48, height: 48)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(DS.C.acc)
                }

                Spacer().frame(height: 20)

                Text("Schicht öffnen")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)

                Spacer().frame(height: 4)

                Text("Geben Sie den aktuellen Kassenbestand ein, um die Schicht zu beginnen.")
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 28)

                // Label
                Text("KASSENBESTAND (€)")
                    .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.5)

                Spacer().frame(height: 6)

                // Betrag-Eingabe
                HStack(spacing: 8) {
                    TextField("0,00", text: $openingCashText)
                        .font(.jakarta(22, weight: .semibold))
                        .foregroundColor(DS.C.text)
                        .keyboardType(.decimalPad)
                        .focused($fieldFocused)
                        .multilineTextAlignment(.trailing)

                    Text("€")
                        .font(.jakarta(18, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(DS.C.bg)
                .cornerRadius(DS.R.input)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.R.input)
                        .strokeBorder(
                            fieldFocused ? DS.C.acc : DS.C.brd(colorScheme),
                            lineWidth: fieldFocused ? 1.5 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: fieldFocused)

                Spacer().frame(height: 8)

                if let cents = openingCents {
                    Text("= \(formatCents(cents))")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .transition(.opacity)
                }

                Spacer().frame(height: 24)

                // Öffnen-Button
                Button {
                    Task { await performOpen() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Schicht öffnen")
                                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.S.buttonHeight)
                }
                .background(canOpen ? DS.C.acc : DS.C.acc.opacity(0.4))
                .cornerRadius(DS.R.button)
                .disabled(!canOpen)
                .animation(.easeInOut(duration: 0.15), value: canOpen)
            }
            .padding(36)
            .frame(width: 440)
            .background(DS.C.sur)
            .cornerRadius(DS.R.card)
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 8)
            .alert("Fehler", isPresented: $showError) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Unbekannter Fehler")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { fieldFocused = true }
    }

    private func performOpen() async {
        guard let cents = openingCents else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await sessionStore.open(openingCashCents: cents)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }
}

// MARK: - Aktive Session

private struct ActiveSessionView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @Binding var showCloseSheet: Bool
    @Binding var showMovementSheet: Bool

    var body: some View {
        guard let session = sessionStore.currentSession else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                // Header
                SessionHeaderBar(session: session, showCloseSheet: $showCloseSheet)

                // Content
                HStack(alignment: .top, spacing: 16) {
                    // Linke Spalte: Stats
                    SessionStatsPanel(session: session)
                        .frame(width: 280)

                    // Rechte Spalte: Movements
                    MovementsPanel(
                        movements: session.movements,
                        showMovementSheet: $showMovementSheet
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        )
    }
}

// MARK: - Session Header Bar

private struct SessionHeaderBar: View {
    let session: CashRegisterSession
    @Binding var showCloseSheet: Bool
    @EnvironmentObject var sessionStore: SessionStore

    var body: some View {
        HStack(spacing: 16) {
            // Status-Chip
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Schicht offen")
                    .font(.jakarta(DS.T.sessionChip, weight: .semibold))
                    .foregroundColor(DS.C.freeText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DS.C.freeBg)
            .cornerRadius(20)

            Text("Eröffnet von \(session.openedByName)")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)

            Text("·")
                .foregroundColor(DS.C.text2)

            Text(formatTimeOnly(session.openedAt))
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)

            Spacer()

            // Schicht schließen
            Button {
                showCloseSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Schicht schließen")
                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Color(hex: "c0392b"))
                .cornerRadius(DS.R.button)
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.C.sur)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(DS.C.brdLight),
            alignment: .bottom
        )
    }
}

// MARK: - Session Stats Panel

private struct SessionStatsPanel: View {
    let session: CashRegisterSession

    private var depositTotal: Int {
        session.movements
            .filter { $0.type == .deposit }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var withdrawalTotal: Int {
        session.movements
            .filter { $0.type == .withdrawal }
            .reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÜBERSICHT")
                .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)

            StatRow(
                icon:  "banknote",
                label: "Eröffnungsbestand",
                value: formatCents(session.openingCashCents),
                color: DS.C.text
            )

            if depositTotal > 0 {
                StatRow(
                    icon:  "plus.circle.fill",
                    label: "Einlagen",
                    value: "+ \(formatCents(depositTotal))",
                    color: DS.C.freeText
                )
            }

            if withdrawalTotal > 0 {
                StatRow(
                    icon:  "minus.circle.fill",
                    label: "Entnahmen",
                    value: "– \(formatCents(withdrawalTotal))",
                    color: Color(hex: "c0392b")
                )
            }

            Divider()

            StatRow(
                icon:  "tray.fill",
                label: "Erwarteter Bestand",
                value: formatCents(session.openingCashCents + depositTotal - withdrawalTotal),
                color: DS.C.acc,
                bold:  true
            )

            Spacer()
        }
        .padding(20)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
    }
}

private struct StatRow: View {
    let icon:  String
    let label: String
    let value: String
    let color: Color
    var bold: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 18)

            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)

            Spacer()

            Text(value)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(color)
        }
    }
}

// MARK: - Movements Panel

private struct MovementsPanel: View {
    let movements: [CashMovement]
    @Binding var showMovementSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BEWEGUNGEN")
                    .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .tracking(0.5)

                Spacer()

                Button {
                    showMovementSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Einlage / Entnahme")
                            .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    }
                    .foregroundColor(DS.C.acc)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(DS.C.accBg)
                    .cornerRadius(DS.R.button)
                }
                .buttonStyle(.plain)
            }

            if movements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(DS.C.text2)
                    Text("Keine Bewegungen")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(movements.enumerated()), id: \.offset) { _, movement in
                            MovementRow(movement: movement)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
    }
}

private struct MovementRow: View {
    let movement: CashMovement
    @Environment(\.colorScheme) private var colorScheme

    private var isDeposit: Bool { movement.type == .deposit }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDeposit ? DS.C.freeBg : Color(hex: "fdecea"))
                    .frame(width: 32, height: 32)
                Image(systemName: isDeposit ? "plus" : "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isDeposit ? DS.C.freeText : Color(hex: "c0392b"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(movement.reason)
                    .font(.jakarta(DS.T.loginBody, weight: .regular))
                    .foregroundColor(DS.C.text)
                    .lineLimit(1)
                Text(movement.type.displayName)
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            Text("\(isDeposit ? "+" : "–") \(formatCents(movement.amountCents))")
                .font(.jakarta(DS.T.loginBody, weight: .semibold))
                .foregroundColor(isDeposit ? DS.C.freeText : Color(hex: "c0392b"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.C.bg)
        .cornerRadius(DS.R.pinRow)
        .overlay(
            RoundedRectangle(cornerRadius: DS.R.pinRow)
                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Schicht schließen Sheet

private struct CloseSessionSheet: View {
    let onClose: (Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var closingCashText = ""
    @State private var isLoading = false
    @FocusState private var focused: Bool

    private var closingCents: Int? { parseCents(closingCashText) }
    private var canClose: Bool { closingCents != nil && !isLoading }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drag Indicator
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)

                    Text("Schicht schließen")
                        .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                        .foregroundColor(DS.C.text)

                    Spacer().frame(height: 4)

                    Text("Zählen Sie den Kassenbestand und geben Sie den tatsächlichen Betrag ein. Der Z-Bericht wird automatisch erstellt.")
                        .font(.jakarta(DS.T.loginBody, weight: .regular))
                        .foregroundColor(DS.C.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 28)

                    Text("TATSÄCHLICHER KASSENBESTAND (€)")
                        .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)

                    Spacer().frame(height: 6)

                    HStack(spacing: 8) {
                        TextField("0,00", text: $closingCashText)
                            .font(.jakarta(22, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .multilineTextAlignment(.trailing)
                        Text("€")
                            .font(.jakarta(18, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(
                                focused ? DS.C.acc : DS.C.brd(colorScheme),
                                lineWidth: focused ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused)

                    Spacer().frame(height: 32)

                    // Buttons
                    HStack(spacing: 10) {
                        Button("Abbrechen") { dismiss() }
                            .font(.jakarta(DS.T.loginButton, weight: .medium))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.button)
                            .buttonStyle(.plain)

                        Button {
                            Task {
                                guard let cents = closingCents else { return }
                                isLoading = true
                                await onClose(cents)
                                isLoading = false
                                dismiss()
                            }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Schicht schließen")
                                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        }
                        .background(canClose ? Color(hex: "c0392b") : Color(hex: "c0392b").opacity(0.4))
                        .cornerRadius(DS.R.button)
                        .disabled(!canClose)
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { focused = true }
    }
}

// MARK: - Einlage / Entnahme Sheet

private struct AddMovementSheet: View {
    let onAdd: (MovementType, Int, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedType: MovementType = .deposit
    @State private var amountText = ""
    @State private var reason = ""
    @State private var isLoading = false
    @FocusState private var amountFocused: Bool

    private var amountCents: Int? { parseCents(amountText) }
    private var canAdd: Bool {
        amountCents != nil && amountCents! > 0 && !reason.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)

                    Text("Einlage / Entnahme")
                        .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                        .foregroundColor(DS.C.text)

                    Spacer().frame(height: 20)

                    // Typ-Toggle
                    HStack(spacing: 8) {
                        ForEach([MovementType.deposit, MovementType.withdrawal], id: \.self) { (type: MovementType) in
                            let selected = selectedType == type
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedType = type }
                            } label: {
                                Text(type.displayName)
                                    .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                    .foregroundColor(selected ? DS.C.acc : DS.C.text2)
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(selected ? DS.C.accBg : DS.C.sur2)
                                    .cornerRadius(DS.R.button)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.R.button)
                                            .strokeBorder(
                                                selected ? DS.C.acc : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer().frame(height: 20)

                    // Betrag
                    Text("BETRAG (€)")
                        .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)

                    Spacer().frame(height: 6)

                    HStack(spacing: 8) {
                        TextField("0,00", text: $amountText)
                            .font(.jakarta(22, weight: .semibold))
                            .foregroundColor(DS.C.text)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.trailing)
                        Text("€")
                            .font(.jakarta(18, weight: .regular))
                            .foregroundColor(DS.C.text2)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(
                                amountFocused ? DS.C.acc : DS.C.brd(colorScheme),
                                lineWidth: amountFocused ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: amountFocused)

                    Spacer().frame(height: 16)

                    // Grund
                    Text("GRUND")
                        .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)

                    Spacer().frame(height: 6)

                    TextField("z.B. Wechselgeld nachgelegt", text: $reason)
                        .font(.jakarta(14, weight: .regular))
                        .foregroundColor(DS.C.text)
                        .padding(.horizontal, 12)
                        .frame(height: DS.S.inputHeight)
                        .background(DS.C.bg)
                        .cornerRadius(DS.R.input)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.input)
                                .strokeBorder(DS.C.brd(colorScheme), lineWidth: 1)
                        )

                    Spacer().frame(height: 28)

                    HStack(spacing: 10) {
                        Button("Abbrechen") { dismiss() }
                            .font(.jakarta(DS.T.loginButton, weight: .medium))
                            .foregroundColor(DS.C.text2)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                            .background(DS.C.sur2)
                            .cornerRadius(DS.R.button)
                            .buttonStyle(.plain)

                        Button {
                            Task {
                                guard let cents = amountCents else { return }
                                isLoading = true
                                await onAdd(selectedType, cents, reason.trimmingCharacters(in: .whitespaces))
                                isLoading = false
                                dismiss()
                            }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Speichern")
                                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                        }
                        .background(canAdd ? DS.C.acc : DS.C.acc.opacity(0.4))
                        .cornerRadius(DS.R.button)
                        .disabled(!canAdd)
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { amountFocused = true }
    }
}

// MARK: - Z-Bericht Zusammenfassung Sheet

private struct ZReportSummarySheet: View {
    let result: CloseSessionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.C.text2.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 24)

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(DS.C.freeBg)
                                .frame(width: 40, height: 40)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(DS.C.freeText)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schicht geschlossen")
                                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                                .foregroundColor(DS.C.text)
                            Text("Z-Bericht #\(result.zReportId)")
                                .font(.jakarta(DS.T.loginBody, weight: .regular))
                                .foregroundColor(DS.C.text2)
                        }
                    }

                    Spacer().frame(height: 28)

                    Text("ABRECHNUNG")
                        .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .tracking(0.5)

                    Spacer().frame(height: 12)

                    VStack(spacing: 0) {
                        ZReportRow(label: "Umsatz gesamt", value: formatCents(result.totalRevenueCents), bold: true)
                        ZReportRow(label: "Bestellungen", value: "\(result.totalOrders)")
                        ZReportRow(label: "Rabatte", value: "– \(formatCents(result.totalDiscountCents))")
                        ZReportRow(label: "Stornos", value: "\(result.cancellationCount)")
                        Divider().padding(.vertical, 8)
                        ZReportRow(label: "Soll-Bestand", value: formatCents(result.expectedCashCents))
                        ZReportRow(label: "Ist-Bestand", value: formatCents(result.closingCashCents))
                        ZReportRow(
                            label: "Differenz",
                            value: (result.differenceCents >= 0 ? "+ " : "– ") + formatCents(abs(result.differenceCents)),
                            valueColor: result.differenceCents == 0
                                ? DS.C.text
                                : (result.differenceCents > 0 ? DS.C.freeText : Color(hex: "c0392b")),
                            bold: true
                        )
                    }

                    Spacer().frame(height: 28)

                    Button {
                        dismiss()
                    } label: {
                        Text("Fertig")
                            .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: DS.S.buttonHeight)
                    }
                    .background(DS.C.acc)
                    .cornerRadius(DS.R.button)
                    .buttonStyle(.plain)

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

private struct ZReportRow: View {
    let label: String
    let value: String
    var valueColor: Color = DS.C.text
    var bold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
            Spacer()
            Text(value)
                .font(.jakarta(DS.T.loginBody, weight: bold ? .semibold : .regular))
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Helpers

private func parseCents(_ text: String) -> Int? {
    let normalized = text
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty,
          let value = Double(normalized),
          value >= 0
    else { return nil }
    return Int((value * 100).rounded())
}

private func formatCents(_ cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100)
}

private func formatTimeOnly(_ iso: String) -> String {
    // "2026-03-16T08:00:00.000Z" → "08:00 Uhr"
    guard iso.count >= 16 else { return iso }
    let start = iso.index(iso.startIndex, offsetBy: 11)
    let end   = iso.index(iso.startIndex, offsetBy: 16)
    return "\(iso[start..<end]) Uhr"
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

#Preview("Offline") {
    KassensitzungView()
        .environmentObject(SessionStore.previewNoSession)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    KassensitzungView()
        .environmentObject(SessionStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

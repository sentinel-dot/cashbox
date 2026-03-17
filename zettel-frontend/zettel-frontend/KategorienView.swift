// KategorienView.swift
// cashbox — Kategorienverwaltung: CRUD für Produktkategorien

import SwiftUI

// MARK: - Root

struct KategorienView: View {
    @EnvironmentObject var productStore:  ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAddSheet  = false
    @State private var editCategory: ProductCategoryRef? = nil
    @State private var deleteTarget: ProductCategoryRef? = nil
    @State private var error:        AppError?
    @State private var showError     = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                KategorienTopBar(onAdd: { showAddSheet = true })

                if productStore.isLoading && productStore.allCategories.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if productStore.allCategories.isEmpty {
                    EmptyKategorien()
                } else {
                    KategorienList(
                        categories: productStore.allCategories,
                        onEdit:   { editCategory = $0 },
                        onDelete: { deleteTarget = $0 }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
        .task { await productStore.loadCategories() }
        .sheet(isPresented: $showAddSheet) {
            KategorieFormSheet(mode: .add) { name, color, sortOrder in
                await performCreate(name: name, color: color, sortOrder: sortOrder)
            }
        }
        .sheet(item: $editCategory) { cat in
            KategorieFormSheet(mode: .edit(cat)) { name, color, sortOrder in
                await performUpdate(id: cat.id, name: name, color: color, sortOrder: sortOrder)
            }
        }
        .confirmationDialog(
            "\"\(deleteTarget?.name ?? "")\" löschen?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let cat = deleteTarget else { return }
                Task { await performDelete(id: cat.id) }
            }
            Button("Abbrechen", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Produkte dieser Kategorie werden keiner Kategorie zugeordnet. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unbekannter Fehler")
        }
    }

    // MARK: - Actions

    private func performCreate(name: String, color: String?, sortOrder: Int) async {
        do {
            try await productStore.createCategory(name: name, color: color, sortOrder: sortOrder)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }

    private func performUpdate(id: Int, name: String?, color: String?, sortOrder: Int?) async {
        do {
            try await productStore.updateCategory(id: id, name: name, color: color, sortOrder: sortOrder)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
    }

    private func performDelete(id: Int) async {
        do {
            try await productStore.deleteCategory(id: id)
        } catch let e as AppError {
            error = e; showError = true
        } catch {
            self.error = .unknown(error.localizedDescription); showError = true
        }
        deleteTarget = nil
    }
}

// MARK: - Top Bar

private struct KategorienTopBar: View {
    let onAdd: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Kategorien")
                    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Produktkategorien verwalten")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Kategorie")
                        .font(.jakarta(DS.T.loginButton, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(DS.C.acc)
                .cornerRadius(DS.R.button)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
    }
}

// MARK: - Empty State

private struct EmptyKategorien: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(DS.C.text2)
            Text("Keine Kategorien")
                .font(.jakarta(DS.T.loginTitle, weight: .semibold))
                .foregroundColor(DS.C.text)
            Text("Erstelle Kategorien um Produkte zu gruppieren.")
                .font(.jakarta(DS.T.loginBody, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Kategorien-Liste

private struct KategorienList: View {
    let categories: [ProductCategoryRef]
    let onEdit:     (ProductCategoryRef) -> Void
    let onDelete:   (ProductCategoryRef) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                    KategorieRow(
                        category: cat,
                        sortOrder: index + 1,
                        onEdit:   { onEdit(cat) },
                        onDelete: { onDelete(cat) }
                    )
                }
            }
            .padding(20)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Kategorie-Row

private struct KategorieRow: View {
    let category:  ProductCategoryRef
    let sortOrder: Int
    let onEdit:    () -> Void
    let onDelete:  () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var accentColor: Color {
        if let hex = category.color { return Color(hex: hex) }
        return DS.C.text2
    }

    var body: some View {
        HStack(spacing: 14) {
            // Farb-Chip
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor)
                    .frame(width: 14, height: 14)
            }

            // Name + Sort-Order
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.jakarta(DS.T.loginBody, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Position \(sortOrder)")
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }

            Spacer()

            // Hex-Farbe anzeigen
            if let hex = category.color {
                Text(hex.uppercased())
                    .font(.jakarta(DS.T.loginFooter, weight: .regular))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.C.bg)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
            }

            // Aktionen
            HStack(spacing: 4) {
                IconButton(icon: "pencil",    color: DS.C.text2, action: onEdit)
                IconButton(icon: "trash",     color: Color(hex: "e74c3c"), action: onDelete)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.C.sur)
        .cornerRadius(DS.R.card)
        .overlay(RoundedRectangle(cornerRadius: DS.R.card).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
    }
}

private struct IconButton: View {
    let icon:   String
    let color:  Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .frame(width: DS.S.touchTarget, height: DS.S.touchTarget)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form Sheet

private enum KategorieFormMode {
    case add
    case edit(ProductCategoryRef)
}

private struct KategorieFormSheet: View {
    let mode:     KategorieFormMode
    let onSave:   (String, String?, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name:      String = ""
    @State private var colorHex:  String = ""
    @State private var sortOrder: String = ""
    @State private var isLoading  = false
    @FocusState private var focusedField: FormField?

    private enum FormField { case name, color, sortOrder }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String { isEditing ? "Kategorie bearbeiten" : "Neue Kategorie" }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // Preset-Farben
    private let colorPresets = [
        "#1a6fff", "#9b59b6", "#e67e22", "#27ae60",
        "#e74c3c", "#f39c12", "#16a085", "#2c3e50"
    ]

    init(mode: KategorieFormMode, onSave: @escaping (String, String?, Int) async -> Void) {
        self.mode   = mode
        self.onSave = onSave
        if case .edit(let cat) = mode {
            _name      = State(initialValue: cat.name)
            _colorHex  = State(initialValue: cat.color ?? "")
            _sortOrder = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Name
                    FormSection("NAME") {
                        TextField("z.B. Getränke", text: $name)
                            .font(.jakarta(14, weight: .regular))
                            .foregroundColor(DS.C.text)
                            .focused($focusedField, equals: .name)
                            .padding(.horizontal, 12)
                            .frame(height: DS.S.inputHeight)
                            .background(DS.C.bg)
                            .cornerRadius(DS.R.input)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.R.input)
                                    .strokeBorder(
                                        focusedField == .name ? DS.C.acc : DS.C.brd(colorScheme),
                                        lineWidth: 1
                                    )
                            )
                    }

                    // Farbe
                    FormSection("FARBE (OPTIONAL)") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Preset-Chips
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                ForEach(colorPresets, id: \.self) { hex in
                                    ColorChip(
                                        hex: hex,
                                        isSelected: colorHex.lowercased() == hex.lowercased()
                                    ) {
                                        colorHex = hex
                                        focusedField = nil
                                    }
                                }
                            }

                            // Manuelles Hex-Input
                            HStack(spacing: 8) {
                                // Vorschau
                                if !colorHex.isEmpty {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(hex: colorHex))
                                        .frame(width: 24, height: 24)
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                                }
                                TextField("#1a6fff", text: $colorHex)
                                    .font(.jakarta(14, weight: .regular))
                                    .foregroundColor(DS.C.text)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .color)
                                    .padding(.horizontal, 12)
                                    .frame(height: DS.S.inputHeight)
                                    .background(DS.C.bg)
                                    .cornerRadius(DS.R.input)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.R.input)
                                            .strokeBorder(
                                                focusedField == .color ? DS.C.acc : DS.C.brd(colorScheme),
                                                lineWidth: 1
                                            )
                                    )
                                if !colorHex.isEmpty {
                                    Button {
                                        colorHex = ""
                                        focusedField = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(DS.C.text2)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Sort-Order (nur bei Neuanlage wirklich relevant)
                    FormSection("POSITION (SORT-ORDER)") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("z.B. 1", text: $sortOrder)
                                .font(.jakarta(14, weight: .regular))
                                .foregroundColor(DS.C.text)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .sortOrder)
                                .padding(.horizontal, 12)
                                .frame(height: DS.S.inputHeight)
                                .background(DS.C.bg)
                                .cornerRadius(DS.R.input)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.R.input)
                                        .strokeBorder(
                                            focusedField == .sortOrder ? DS.C.acc : DS.C.brd(colorScheme),
                                            lineWidth: 1
                                        )
                                )
                            Text("Leer lassen = ans Ende anfügen")
                                .font(.jakarta(DS.T.loginFooter, weight: .regular))
                                .foregroundColor(DS.C.text2)
                        }
                    }
                }
                .padding(20)
            }
            .background(DS.C.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .font(.jakarta(DS.T.loginButton, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Text(isEditing ? "Speichern" : "Erstellen")
                                    .font(.jakarta(DS.T.loginButton, weight: .semibold))
                            }
                        }
                    }
                    .disabled(!canSave || isLoading)
                    .foregroundColor(canSave ? DS.C.acc : DS.C.text2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)
        let trimmedColor = colorHex.trimmingCharacters(in: .whitespaces)
        let parsedOrder  = Int(sortOrder) ?? 999
        let colorArg: String? = trimmedColor.isEmpty ? nil : trimmedColor
        await onSave(trimmedName, colorArg, parsedOrder)
        dismiss()
    }
}

// MARK: - Hilfstrukturen

private struct FormSection<Content: View>: View {
    let title:   String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.jakarta(DS.T.sectionHeader, weight: .semibold))
                .foregroundColor(DS.C.text2)
                .tracking(0.5)
            content
        }
    }
}

private struct ColorChip: View {
    let hex:        String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(height: 34)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? .white.opacity(0.8) : .clear, lineWidth: 2)
        )
    }
}

// MARK: - Previews

#Preview("Mit Kategorien") {
    KategorienView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Leer") {
    KategorienView()
        .environmentObject(ProductStore.previewEmpty)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Dark Mode") {
    KategorienView()
        .environmentObject(ProductStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}

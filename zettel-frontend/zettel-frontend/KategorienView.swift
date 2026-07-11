// KategorienView.swift
// cashbox — Kategorienverwaltung: Liste links + Detail-Panel rechts
// Design v3: keine toten Drag-Affordanzen, 44pt-Aktionen, DS-Komponenten.

import SwiftUI

// MARK: - Root

struct KategorienView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var selectedId:   Int?               = nil
    @State private var showAddModal  = false
    @State private var deleteTarget: ProductCategoryRef? = nil
    @State private var error:        AppError?
    @State private var showError     = false

    private var selectedCategory: ProductCategoryRef? {
        productStore.allCategories.first { $0.id == selectedId }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.C.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isOnline {
                    OfflineBanner()
                        .dsBannerTransition()
                }

                KategorienToolbar(count: productStore.allCategories.count, onAdd: { showAddModal = true })

                if productStore.isLoading && productStore.allCategories.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if productStore.allCategories.isEmpty {
                    DSEmptyState(
                        icon: "folder.badge.plus",
                        title: "Keine Kategorien",
                        message: "Erstelle Kategorien, um Produkte zu gruppieren.",
                        actionLabel: "Kategorie hinzufügen",
                        action: { showAddModal = true }
                    )
                } else {
                    HStack(spacing: 0) {
                        KategorienListe(
                            categories:       productStore.allCategories,
                            products:         productStore.products,
                            selectedId:       $selectedId,
                            onDelete:         { deleteTarget = $0 }
                        )

                        KategorienDetailPanel(
                            category:       selectedCategory,
                            products:       productStore.products,
                            allCategories:  productStore.allCategories,
                            onSave:         { id, name, color, sortOrder in
                                Task { await performUpdate(id: id, name: name, color: color, sortOrder: sortOrder) }
                            },
                            onDeselect:     { selectedId = nil }
                        )
                        .frame(width: 360)
                        .overlay(Rectangle().frame(width: 1).foregroundColor(DS.C.brdAdaptive), alignment: .leading)
                    }
                }
            }
        }
        .animation(DS.M.base, value: networkMonitor.isOnline)
        .task { await productStore.loadCategories() }
        .sheet(isPresented: $showAddModal) {
            NeueKategorieSheet { name, color, sortOrder in
                await performCreate(name: name, color: color, sortOrder: sortOrder)
                showAddModal = false
            }
        }
        .confirmationDialog(
            "\"\(deleteTarget?.name ?? "")\" löschen?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                guard let cat = deleteTarget else { return }
                if selectedId == cat.id { selectedId = nil }
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

    // MARK: Actions

    private func performCreate(name: String, color: String?, sortOrder: Int) async {
        do {
            try await productStore.createCategory(name: name, color: color, sortOrder: sortOrder)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func performUpdate(id: Int, name: String, color: String?, sortOrder: Int?) async {
        do {
            try await productStore.updateCategory(id: id, name: name, color: color, sortOrder: sortOrder)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
    }

    private func performDelete(id: Int) async {
        do {
            try await productStore.deleteCategory(id: id)
        } catch let e as AppError { error = e; showError = true }
        catch { self.error = .unknown(error.localizedDescription); showError = true }
        deleteTarget = nil
    }
}

// MARK: - Toolbar

private struct KategorienToolbar: View {
    let count: Int
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kategorien")
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
                Text("\(count) Kategorie\(count == 1 ? "" : "n") · Reihenfolge bestimmt die Anzeige an der Kasse")
                    .dsFont(.caption)
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .dsFont(.raw(14, weight: .bold))
                    Text("Kategorie hinzufügen")
                }
            }
            .buttonStyle(DSPrimaryButton(height: 42, fullWidth: false))
        }
        .padding(.horizontal, DS.S.pagePad)
        .frame(height: DS.S.topbarHeight + 8)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)
    }
}

// MARK: - Kategorien-Liste (links)

private struct KategorienListe: View {
    let categories: [ProductCategoryRef]
    let products:   [Product]
    @Binding var selectedId: Int?
    let onDelete:   (ProductCategoryRef) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, cat in
                    let prodCount = products.filter { $0.category?.id == cat.id }.count
                    KategorieCard(
                        category:   cat,
                        sortOrder:  index + 1,
                        prodCount:  prodCount,
                        isSelected: selectedId == cat.id,
                        onSelect:   { selectedId = cat.id },
                        onDelete:   { onDelete(cat) }
                    )
                }
            }
            .padding(DS.S.pagePad)
        }
        .background(DS.C.bg)
    }
}

// MARK: - Kategorie-Card

private struct KategorieCard: View {
    let category:   ProductCategoryRef
    let sortOrder:  Int
    let prodCount:  Int
    let isSelected: Bool
    let onSelect:   () -> Void
    let onDelete:   () -> Void

    var accentColor: Color {
        Color(hex: category.color ?? "#888888")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Farbiges Icon-Quadrat
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: "tag.fill")
                        .dsFont(.raw(16))
                        .foregroundColor(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .dsFont(.raw(16, weight: .semibold))
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text)
                    Text("\(prodCount) Produkt\(prodCount == 1 ? "" : "e") · Sortierung \(sortOrder)")
                        .dsFont(.caption, monoDigits: true)
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .dsFont(.raw(14, weight: .medium))
                        .foregroundColor(DS.C.dangerText)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: DS.R.control).fill(DS.C.dangerBg.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .dsFont(.raw(13, weight: .semibold))
                    .foregroundColor(DS.C.text2.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .fill(isSelected ? DS.C.accBg : DS.C.sur)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.R.card)
                    .strokeBorder(isSelected ? DS.C.acc : DS.C.brdAdaptive, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.R.card))
        }
        .buttonStyle(.plain)
        .animation(DS.M.fast, value: isSelected)
    }
}

// MARK: - Detail-Panel (rechts)

private struct KategorienDetailPanel: View {
    let category:      ProductCategoryRef?
    let products:      [Product]
    let allCategories: [ProductCategoryRef]
    let onSave:        (Int, String, String?, Int?) -> Void
    let onDeselect:    () -> Void

    var body: some View {
        if let cat = category {
            DetailContent(
                category:      cat,
                products:      products,
                allCategories: allCategories,
                onSave:        onSave,
                onCancel:      onDeselect
            )
            .id(cat.id)  // Reset form state when selection changes
            .background(DS.C.sur)
        } else {
            DSEmptyState(
                icon: "square.grid.2x2",
                title: "Kategorie auswählen",
                message: "Tippe links auf eine Kategorie, um sie zu bearbeiten."
            )
            .background(DS.C.sur)
        }
    }
}

private struct DetailContent: View {
    let category:      ProductCategoryRef
    let products:      [Product]
    let allCategories: [ProductCategoryRef]
    let onSave:        (Int, String, String?, Int?) -> Void
    let onCancel:      () -> Void

    @State private var name       = ""
    @State private var colorHex   = ""
    @State private var sortText   = ""
    @State private var nameFocused = false

    // Datenfarben in der Ledger-Signatur: gedämpfte, erdige Mitteltöne —
    // unterscheidbar, aber kein Regenbogen neben dem Restrained-Grün
    private let colorPresets = ["4a7310","9a6a0b","b4552d","9e2f42","6e5a9e","3a7ca5","2e8c81","6b7267"]

    private var assignedProducts: [Product] {
        products.filter { $0.category?.id == category.id }
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(hex: colorHex.isEmpty ? (category.color ?? "888888") : colorHex))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? category.name : name)
                        .dsFont(.heading)
                        .foregroundColor(DS.C.text)
                    Text("\(assignedProducts.count) Produkt\(assignedProducts.count == 1 ? "" : "e") zugewiesen")
                        .dsFont(.caption)
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)

            // Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Name
                    DetailField(label: "Name") {
                        DSTextField(placeholder: "z.B. Getränke", text: $name,
                                    capitalization: .sentences, autocorrection: .default)
                    }

                    // Farbe
                    DetailField(label: "Farbe") {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                            spacing: 8
                        ) {
                            ForEach(colorPresets, id: \.self) { hex in
                                DetailColorSwatch(hex: hex, isSelected: colorHex.lowercased().trimmingCharacters(in: .init(charactersIn: "#")) == hex.lowercased()) {
                                    colorHex = "#\(hex)"
                                }
                            }
                        }
                        // HEX-Anzeige
                        HStack(spacing: 8) {
                            if !colorHex.isEmpty {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 22, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.C.brdAdaptive, lineWidth: 1))
                            }
                            Text(colorHex.isEmpty ? "Eigener HEX-Wert" : colorHex.uppercased())
                                .dsFont(.mono(13))
                                .foregroundColor(colorHex.isEmpty ? DS.C.text2 : DS.C.text)
                            Spacer()
                            if !colorHex.isEmpty {
                                Button { colorHex = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .dsFont(.raw(15))
                                        .foregroundColor(DS.C.text2)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Zugewiesene Produkte
                    if !assignedProducts.isEmpty {
                        DetailField(label: "Zugewiesene Produkte") {
                            let shown = Array(assignedProducts.prefix(6))
                            let rest  = assignedProducts.count - shown.count
                            FlexWrap(spacing: 6) {
                                ForEach(shown) { p in
                                    Text(p.name)
                                        .dsFont(.caption)
                                        .foregroundColor(DS.C.text)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Capsule().fill(DS.C.sur2))
                                }
                                if rest > 0 {
                                    Text("+ \(rest) weitere")
                                        .dsFont(.caption)
                                        .foregroundColor(DS.C.text2)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Capsule().fill(DS.C.sur2))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            // Footer
            HStack(spacing: 10) {
                Button("Abbrechen") { onCancel() }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))

                Spacer()

                Button {
                    let trimName  = name.trimmingCharacters(in: .whitespaces)
                    let colorArg: String? = colorHex.trimmingCharacters(in: .whitespaces).isEmpty ? nil : colorHex
                    let sortArg:  Int?    = Int(sortText)
                    onSave(category.id, trimName, colorArg, sortArg)
                } label: {
                    Text("Speichern")
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
        .onAppear {
            name     = category.name
            colorHex = category.color ?? ""
        }
    }
}

private struct DetailField<Content: View>: View {
    let label:   String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSSectionLabel(text: label)
            content
        }
    }
}

private struct DetailColorSwatch: View {
    let hex:        String
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#\(hex)"))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: 2)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .dsFont(.raw(12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.07 : 1.0)
        .animation(DS.M.fast, value: isSelected)
    }
}

// MARK: - FlexWrap (für Produkt-Chips)

private struct FlexWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
    }
}

// MARK: - Neue Kategorie Modal (Sheet)

private struct NeueKategorieSheet: View {
    let onSave: (String, String?, Int) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name       = ""
    @State private var colorHex   = ""
    @State private var isSaving   = false
    @State private var nameFocused = false

    // Datenfarben in der Ledger-Signatur: gedämpfte, erdige Mitteltöne —
    // unterscheidbar, aber kein Regenbogen neben dem Restrained-Grün
    private let colorPresets = ["4a7310","9a6a0b","b4552d","9e2f42","6e5a9e","3a7ca5","2e8c81","6b7267"]

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Neue Kategorie")
                    .dsFont(.heading)
                    .foregroundColor(DS.C.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .dsFont(.raw(13, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DS.C.sur2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .bottom)

            // Body
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    DSTextField(label: "Name",
                                placeholder: "z.B. Heißgetränke", text: $name,
                                capitalization: .sentences, autocorrection: .default)
                }

                VStack(alignment: .leading, spacing: 8) {
                    DSSectionLabel(text: "Farbe")
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8),
                        spacing: 8
                    ) {
                        ForEach(colorPresets, id: \.self) { hex in
                            DetailColorSwatch(
                                hex:        hex,
                                isSelected: colorHex.lowercased().trimmingCharacters(in: .init(charactersIn: "#")) == hex
                            ) {
                                colorHex = "#\(hex)"
                            }
                        }
                    }
                }
            }
            .padding(20)

            // Footer
            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(DSSecondaryButton(height: 48, fullWidth: false))

                Spacer()

                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    Task {
                        let colorArg: String? = colorHex.isEmpty ? nil : colorHex
                        await onSave(name.trimmingCharacters(in: .whitespaces), colorArg, 999)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("Kategorie speichern")
                        }
                    }
                }
                .buttonStyle(DSPrimaryButton(height: 48, fullWidth: false))
                .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdAdaptive), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // Formular — kein versehentliches Weg-Wischen
        .interactiveDismissDisabled(!name.trimmingCharacters(in: .whitespaces).isEmpty)
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

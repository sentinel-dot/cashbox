// KategorienView.swift
// cashbox — Kategorienverwaltung: 2-Spalten-Layout nach Referenz-Design

import SwiftUI

// MARK: - Root

struct KategorienView: View {
    @EnvironmentObject var productStore:   ProductStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.colorScheme) private var colorScheme

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
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                KategorienToolbar(count: productStore.allCategories.count, onAdd: { showAddModal = true })

                if productStore.isLoading && productStore.allCategories.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if productStore.allCategories.isEmpty {
                    EmptyKategorien()
                } else {
                    HStack(spacing: 0) {
                        // Links: Kategorienliste
                        KategorienListe(
                            categories:       productStore.allCategories,
                            products:         productStore.products,
                            selectedId:       $selectedId,
                            onDelete:         { deleteTarget = $0 }
                        )

                        // Rechts: Detail-Panel (340px)
                        KategorienDetailPanel(
                            category:       selectedCategory,
                            products:       productStore.products,
                            allCategories:  productStore.allCategories,
                            onSave:         { id, name, color, sortOrder in
                                Task { await performUpdate(id: id, name: name, color: color, sortOrder: sortOrder) }
                            },
                            onDeselect:     { selectedId = nil }
                        )
                        .frame(width: 340)
                        .overlay(Rectangle().frame(width: 1).foregroundColor(DS.C.brdLight), alignment: .leading)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: networkMonitor.isOnline)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kategorien")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Text("Reihenfolge per Drag & Drop änderbar")
                    .font(.jakarta(11, weight: .regular))
                    .foregroundColor(DS.C.text2)
            }
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Kategorie hinzufügen")
                        .font(.jakarta(DS.T.loginFooter + 1, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
            }
            .background(DS.C.acc)
            .cornerRadius(DS.R.button)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: DS.S.topbarHeight)
        .background(DS.C.sur)
        .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)
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
            VStack(alignment: .leading, spacing: 10) {
                // Sort-Hint
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundColor(DS.C.text2)
                    Text("Reihenfolge bestimmt die Anzeige im Kassensystem")
                        .font(.jakarta(10, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                .padding(.bottom, 2)

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
            .padding(20)
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

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

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
                        .frame(width: 40, height: 40)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                }

                // Name + Meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(isSelected ? DS.C.accT : DS.C.text)
                    Text("\(prodCount) Produkt\(prodCount == 1 ? "" : "e") · Sortierung: \(sortOrder)")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }

                Spacer()

                // Active badge (immer aktiv, da kein isActive-Feld im Modell)
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.C.freeText)
                        .frame(width: 5, height: 5)
                    Text("Aktiv")
                        .font(.jakarta(10, weight: .semibold))
                        .foregroundColor(DS.C.freeText)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(DS.C.freeBg)
                .cornerRadius(20)

                // Action-Buttons
                HStack(spacing: 6) {
                    CardActionBtn(icon: "pencil",   isDanger: false) { onSelect() }
                    CardActionBtn(icon: "trash",    isDanger: true)  { onDelete() }
                }

                // Drag-Handle
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(isHovered ? DS.C.text2 : DS.C.brdLight)
                            .frame(width: 16, height: 2)
                            .cornerRadius(1)
                    }
                }
                .frame(width: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? DS.C.accBg : DS.C.sur)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected
                            ? DS.C.acc
                            : (isHovered ? DS.C.acc.opacity(0.2) : DS.C.brd(colorScheme)),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

private struct CardActionBtn: View {
    let icon:     String
    let isDanger: Bool
    let action:   () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? (isDanger ? DS.C.dangerText : DS.C.text) : DS.C.text2)
                .frame(width: 28, height: 28)
                .background(isHovered ? (isDanger ? DS.C.dangerBg : DS.C.sur2) : Color.clear)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isHovered ? (isDanger ? DS.C.dangerText.opacity(0.4) : DS.C.brd(colorScheme)) : DS.C.brd(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
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
            DetailEmpty()
                .background(DS.C.sur)
        }
    }
}

private struct DetailEmpty: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.C.sur2)
                    .frame(width: 48, height: 48)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(DS.C.text2)
            }
            Text("Kategorie auswählen")
                .font(.jakarta(13, weight: .medium))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
            Text("Tippe auf eine Kategorie um sie zu bearbeiten.")
                .font(.jakarta(11, weight: .regular))
                .foregroundColor(DS.C.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DetailContent: View {
    let category:      ProductCategoryRef
    let products:      [Product]
    let allCategories: [ProductCategoryRef]
    let onSave:        (Int, String, String?, Int?) -> Void
    let onCancel:      () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var name       = ""
    @State private var colorHex   = ""
    @State private var sortText   = ""
    @State private var nameFocused = false

    private let colorPresets = ["1a6fff","3aada0","d4a017","7c5cbf","e05a2b","3a6b35","c0112a","888780"]

    private var assignedProducts: [Product] {
        products.filter { $0.category?.id == category.id }
    }

    private var sortIndex: Int {
        (allCategories.firstIndex(where: { $0.id == category.id }) ?? 0) + 1
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(hex: colorHex.isEmpty ? (category.color ?? "888888") : colorHex))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? category.name : name)
                        .font(.jakarta(15, weight: .semibold))
                        .foregroundColor(DS.C.text)
                    Text("\(assignedProducts.count) Produkt\(assignedProducts.count == 1 ? "" : "e") zugewiesen")
                        .font(.jakarta(11, weight: .regular))
                        .foregroundColor(DS.C.text2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Body
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    // Name
                    DetailField(label: "Name") {
                        NoAssistantTextField(
                            placeholder: "z.B. Getränke",
                            text:        $name,
                            uiFont:      UIFont.systemFont(ofSize: 13),
                            uiTextColor: UIColor(DS.C.text),
                            isFocused:   $nameFocused
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(DS.C.bg)
                        .cornerRadius(DS.R.input)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.R.input)
                                .strokeBorder(nameFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
                        )
                    }

                    // Farbe
                    DetailField(label: "Farbe") {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6),
                            spacing: 7
                        ) {
                            ForEach(colorPresets, id: \.self) { hex in
                                DetailColorSwatch(hex: hex, isSelected: colorHex.lowercased().trimmingCharacters(in: .init(charactersIn: "#")) == hex.lowercased()) {
                                    colorHex = "#\(hex)"
                                }
                            }
                        }
                        // HEX-Eingabe
                        HStack(spacing: 8) {
                            if !colorHex.isEmpty {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 20, height: 20)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                            }
                            Text(colorHex.isEmpty ? "Eigener HEX-Wert" : colorHex.uppercased())
                                .font(.jakarta(11, weight: .regular))
                                .foregroundColor(colorHex.isEmpty ? DS.C.text2 : DS.C.text)
                            Spacer()
                            if !colorHex.isEmpty {
                                Button { colorHex = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(DS.C.text2)
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
                                        .font(.jakarta(11, weight: .medium))
                                        .foregroundColor(DS.C.text2)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(DS.C.sur2)
                                        .cornerRadius(20)
                                }
                                if rest > 0 {
                                    Text("+ \(rest) weitere")
                                        .font(.jakarta(11, weight: .medium))
                                        .foregroundColor(DS.C.text2)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(DS.C.sur2)
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            // Footer
            HStack(spacing: 8) {
                Button("Abbrechen") { onCancel() }
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 16).frame(height: 38)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                    .buttonStyle(.plain)

                Spacer()

                Button {
                    let trimName  = name.trimmingCharacters(in: .whitespaces)
                    let colorArg: String? = colorHex.trimmingCharacters(in: .whitespaces).isEmpty ? nil : colorHex
                    let sortArg:  Int?    = Int(sortText)
                    onSave(category.id, trimName, colorArg, sortArg)
                } label: {
                    Text("Änderungen speichern")
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).frame(height: 38)
                }
                .background(canSave ? DS.C.acc : DS.C.acc.opacity(0.35))
                .cornerRadius(DS.R.button)
                .disabled(!canSave)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
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
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                .foregroundColor(DS.C.text2)
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
                            .strokeBorder(isSelected ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.07 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var name       = ""
    @State private var colorHex   = ""
    @State private var isSaving   = false
    @State private var nameFocused = false

    private let colorPresets = ["1a6fff","3aada0","d4a017","7c5cbf","e05a2b","3a6b35","c0112a","888780"]

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Neue Kategorie")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(DS.C.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.C.text2)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .bottom)

            // Body
            VStack(alignment: .leading, spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 5) {
                    Text("NAME")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    NoAssistantTextField(
                        placeholder: "z.B. Heißgetränke",
                        text:        $name,
                        uiFont:      UIFont.systemFont(ofSize: 13),
                        uiTextColor: UIColor(DS.C.text),
                        isFocused:   $nameFocused
                    )
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(DS.C.bg)
                    .cornerRadius(DS.R.input)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.R.input)
                            .strokeBorder(nameFocused ? DS.C.acc : DS.C.brd(colorScheme), lineWidth: 1)
                    )
                }

                // Farbe
                VStack(alignment: .leading, spacing: 8) {
                    Text("FARBE")
                        .font(.jakarta(9, weight: .semibold)).kerning(0.5)
                        .foregroundColor(DS.C.text2)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8),
                        spacing: 7
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
            HStack(spacing: 8) {
                Button("Abbrechen") { dismiss() }
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(DS.C.text2)
                    .padding(.horizontal, 16).frame(height: 38)
                    .overlay(RoundedRectangle(cornerRadius: DS.R.button).strokeBorder(DS.C.brd(colorScheme), lineWidth: 1))
                    .buttonStyle(.plain)

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
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                        } else {
                            Text("Kategorie speichern")
                                .font(.jakarta(12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                }
                .background(canSave ? DS.C.acc : DS.C.acc.opacity(0.35))
                .cornerRadius(DS.R.button)
                .disabled(!canSave || isSaving)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(DS.C.brdLight), alignment: .top)
        }
        .background(DS.C.sur)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
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

Scaffolde eine neue SwiftUI View für das Kassensystem iPad-App.

**Was du erstellst:**

Eine vollständige View-Datei unter `zettel-frontend/zettel-frontend/<Name>View.swift` mit:

---

### 1. Dateistruktur & Imports

```swift
// <Name>View.swift
// cashbox — <Kurzbeschreibung>

import SwiftUI
```

Alle Files liegen **flach** in `zettel-frontend/zettel-frontend/` — kein `App/Views/`-Unterordner.
Xcode verwendet `PBXFileSystemSynchronizedRootGroup` → neue Dateien kompilieren automatisch, keine pbxproj-Änderung nötig.

---

### 2. Grundstruktur

```swift
struct <Name>View: View {
    // Stores via @EnvironmentObject (nie @StateObject für shared stores)
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    // Lokaler UI-State via @State
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var showError = false

    // colorScheme für DS.C.brd(_:) Border-Farben
    @Environment(\.colorScheme) private var colorScheme

    var body: some View { ... }
}
```

**Nur die Stores einbinden, die die View tatsächlich nutzt.**
Aktuell existierende Stores: `AuthStore`, `NetworkMonitor`.
Noch nicht implementiert (Phase 1+): `OrderStore`, `SessionStore`, `SyncManager`.

---

### 3. Design System — immer DS.* verwenden

```swift
// Farben
DS.C.bg          // Seiten-Hintergrund
DS.C.sur         // Card/Panel-Fläche (weiß / dunkelgrau)
DS.C.sur2        // Sekundäre Fläche, Inputs, Buttons
DS.C.text        // Primärer Text
DS.C.text2       // Sekundärer Text, Labels, Hints
DS.C.acc         // Electric Blue — Akzent, CTA-Buttons, Fokus-Rahmen
DS.C.accBg       // Heller Akzent-Hintergrund (aktive Zustände)
DS.C.accT        // Text auf accBg-Hintergrund
DS.C.brd(colorScheme)  // Border (scheme-abhängig, nie hardcoden)

// Schriftgrößen
DS.T.loginTitle  // 19pt — Überschriften in Panels
DS.T.loginBody   // 12pt — Fließtext
DS.T.loginButton // 13pt — Button-Labels
DS.T.loginFooter // 10pt — Footer, Hints
DS.T.sectionHeader // 9pt — Abschnittsüberschriften
// + weitere siehe DesignSystem.swift

// Radii
DS.R.button      // 9pt — Buttons
DS.R.input       // 9pt — Text-Eingabefelder
DS.R.card        // 14pt — Cards
DS.R.pinRow      // 10pt — Listen-Zeilen

// Größen
DS.S.inputHeight    // 40pt — Eingabefeld-Höhe
DS.S.buttonHeight   // 42pt — Button-Höhe
DS.S.touchTarget    // 44pt — Mindest-Touch-Target (nie unterschreiten)
DS.S.formPanelWidth // 400pt — Formular-Panel (Login/Register-Layout)

// Schrift — immer Font.jakarta statt .system direkt
Text("Label")
    .font(.jakarta(DS.T.loginTitle, weight: .semibold))
    .foregroundColor(DS.C.text)
```

---

### 4. Offline-Awareness (immer einbauen)

```swift
if !networkMonitor.isOnline {
    OfflineBanner()
        .transition(.move(edge: .top).combined(with: .opacity))
}
```

---

### 5. Error Handling (exaktes Muster)

```swift
// State
@State private var error: AppError?
@State private var showError = false

// Im catch-Block:
} catch let appError as AppError {
    error = appError
    showError = true
} catch {
    self.error = .unknown(error.localizedDescription)
    showError = true
}

// Alert (an der äußersten View)
.alert("Fehler", isPresented: $showError) {
    Button("OK") { error = nil }
} message: {
    Text(error?.localizedDescription ?? "Unbekannter Fehler")
}
```

---

### 6. Loading States (exaktes Muster)

```swift
Button {
    Task { await performAction() }
} label: {
    Group {
        if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        } else {
            Text("Bestätigen")
                .font(.jakarta(DS.T.loginButton, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    .frame(maxWidth: .infinity)
    .frame(height: DS.S.buttonHeight)
}
.background(DS.C.acc)
.cornerRadius(DS.R.button)
.disabled(isLoading)
.opacity(isLoading ? 0.6 : 1.0)

private func performAction() async {
    isLoading = true
    defer { isLoading = false }
    do {
        try await someStore.doSomething()
    } catch let appError as AppError {
        error = appError
        showError = true
    } catch {
        self.error = .unknown(error.localizedDescription)
        showError = true
    }
}
```

---

### 7. Input-Felder (Border-Muster)

```swift
TextField("Placeholder", text: $value)
    .font(.jakarta(14, weight: .regular))
    .foregroundColor(DS.C.text)
    .focused($isFocused)
    .padding(.horizontal, 12)
    .frame(height: DS.S.inputHeight)
    .background(DS.C.bg)
    .cornerRadius(DS.R.input)
    .overlay(
        RoundedRectangle(cornerRadius: DS.R.input)
            .strokeBorder(
                isFocused ? DS.C.acc : DS.C.brd(colorScheme),
                lineWidth: 1
            )
    )
    .animation(.easeInOut(duration: 0.15), value: isFocused)
```

---

### 8. iPad-Optimierung

- `NavigationSplitView` für Master-Detail-Layouts
- Mindest-Touch-Target: `DS.S.touchTarget` (44pt) — nie unterschreiten
- Landscape-first (iPad wird quer gehalten im Betrieb)
- Kein `NavigationView` (deprecated)
- 2-Spalten-Layout (Brand-Fläche + Formular) wie in LoginView/RegisterView für Auth-Screens

---

### 9. Deaktivierte Features (nicht implementieren)

- Kein Trinkgeld-UI (Phase 3+)
- Kein Außer-Haus-Toggle aktiv (Phase 4+)
- Kein Drucker/PrinterManager (Phase 5+)
- Kein Multi-iPad Sync (Phase 5+)

---

### 10. Preview (exaktes Muster)

```swift
#Preview("<Beschreibung>") {
    <Name>View()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
}

#Preview("Offline") {
    <Name>View()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.previewOffline)
}

#Preview("Dark Mode") {
    <Name>View()
        .environmentObject(AuthStore.preview)
        .environmentObject(NetworkMonitor.preview)
        .preferredColorScheme(.dark)
}
```

Verfügbare Preview-Factories:
- `AuthStore.preview` — 3 User: Niko (owner), Sara (staff), Mehmet (manager)
- `AuthStore.previewLoggedIn` — isAuthenticated = true, currentUser = Niko
- `NetworkMonitor.preview` — isOnline = true
- `NetworkMonitor.previewOffline` — isOnline = false

---

### 11. Stores & Datenmodelle

**AuthStore** (`currentUser: AuthUser?`, `isAuthenticated: Bool`, `availableUsers: [AuthUser]`)
```swift
// AuthUser — schlankes Login-Modell (id, name, role)
struct AuthUser: Codable, Identifiable {
    let id: Int
    let name: String
    let role: UserRole  // .owner / .manager / .staff
}
// user.role.displayName → "Owner" / "Manager" / "Staff"
```

**NetworkMonitor** (`isOnline: Bool`)

**APIClient.shared** — für direkte HTTP-Calls aus Views (selten, meistens Store delegieren)
```swift
// Encoder/Decoder automatisch camelCase ↔ snake_case
let result: MyModel = try await APIClient.shared.get("/some/endpoint")
let result: MyModel = try await APIClient.shared.post("/some/endpoint", body: body)
```

---

### Stores und wann welcher gebraucht wird

| Store | Wann | Status |
|-------|------|--------|
| `AuthStore` | User-Info, Logout, Permissions, Login | ✅ implementiert |
| `NetworkMonitor` | isOnline — immer einbinden | ✅ implementiert |
| `OrderStore` | Bestellungen, Tischstatus, Items | ❌ Phase 1 (noch nicht) |
| `SessionStore` | Kassensitzung offen/geschlossen | ❌ Phase 1 (noch nicht) |
| `SyncManager` | Offline-Queue-Status anzeigen | ❌ Phase 3 |

---

**Format der Eingabe:** Beschreibe die View, z.B.:
- "TableGridView — Tischgitter nach Zonen, Tischstatus-Kacheln, Kassen-Session-Chip"
- "OrderView — offene Bestellung für Tisch, Produktgitter, Warenkorb mit Summe"
- "SessionView — Kassensitzung öffnen/schließen mit Bargeld-Eingabe"
- "ModifierSheet — Bottom Sheet für Produktvarianten, Pflichtauswahl-Validierung"

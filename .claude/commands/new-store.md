Erstelle einen neuen SwiftUI Store (ObservableObject) für das Kassensystem.

**Stores sind @MainActor ObservableObjects** — sie halten den App-State und kapseln alle API-Calls. Views greifen nie direkt auf APIClient zu, sondern delegieren an einen Store.

## Was du erstellst

Eine Store-Datei unter `zettel-frontend/zettel-frontend/<Name>Store.swift` nach diesem Muster:

```swift
// <Name>Store.swift
// cashbox — <Kurzbeschreibung>

import Foundation

@MainActor
final class <Name>Store: ObservableObject {

    // ── Published State ────────────────────────────────────────────────────
    @Published private(set) var items: [<Model>] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    // ── Dependencies ───────────────────────────────────────────────────────
    private let api = APIClient.shared

    // ── Public Interface ───────────────────────────────────────────────────

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.get("/<endpoint>")
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    // ── Preview Factory ────────────────────────────────────────────────────

    static var preview: <Name>Store {
        let store = <Name>Store()
        // store.items = [<Beispieldaten>]
        return store
    }

    static var previewEmpty: <Name>Store {
        <Name>Store()
    }
}
```

---

## Kritische Patterns

**1. Immer `@MainActor final class`** — nie `struct`, nie ohne `@MainActor`

**2. `private(set)` für alle @Published** — Views lesen, mutieren nie direkt

**3. Fehler immer als `AppError`** — nie rohe `Error`-Typen nach oben durchreichen

**4. API-Calls immer in `async` Funktionen** — Views rufen diese via `Task { await store.load() }` auf

**5. `defer { isLoading = false }`** — garantiert Reset auch bei Fehler

---

## Injection in zettel_frontendApp.swift

Nach Fertigstellung **immer** in `zettel_frontendApp.swift` als `@StateObject` anlegen und als `.environmentObject()` injizieren:

```swift
@StateObject private var <name>Store = <Name>Store()

// In WindowGroup:
ContentView()
    .environmentObject(<name>Store)
```

Und in Views die den Store brauchen:
```swift
@EnvironmentObject var <name>Store: <Name>Store
```

---

## Existierende Stores (nie doppelt anlegen)

| Store | Status | Datei |
|-------|--------|-------|
| `AuthStore` | ✅ implementiert | AuthStore.swift |
| `NetworkMonitor` | ✅ implementiert | NetworkMonitor.swift |
| `OrderStore` | ❌ Phase 1 | noch nicht erstellt |
| `SessionStore` | ❌ Phase 1 | noch nicht erstellt |
| `SyncManager` | ❌ Phase 3 | noch nicht erstellt |

---

## Datenmodelle (Models.swift)

Neue Modelle die der Store braucht kommen in `Models.swift` (nicht in den Store selbst).
Modelle sind `Codable + Identifiable`. APIClient nutzt `snake_case` decoder automatisch.

```swift
struct MyModel: Codable, Identifiable {
    let id: Int
    let name: String
    let createdAt: Date  // snake_case → camelCase automatisch via APIClient
}
```

---

## Pflicht nach Implementierung: CLAUDE.md aktualisieren

1. **"SwiftUI — Offene Punkte"** — Store aus der Liste entfernen
2. **"Fertig implementiert ✅"** — Store eintragen
3. **`new-swiftui-view.md` Stores-Tabelle** — Status von ❌ auf ✅ setzen

---

**Format der Eingabe:** Beschreibe den Store kurz, z.B.:
- "OrderStore — offene Bestellungen laden, Item hinzufügen/entfernen, Order stornieren"
- "SessionStore — aktuelle Kassensitzung laden, öffnen, schließen, Movements"
- "ProductStore — Produktkatalog laden (inkl. Kategorien + Modifier), Offline-Cache"

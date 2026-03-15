Scaffolde eine neue SwiftUI View für das Kassensystem iPad-App.

**Was du erstellst:**

Eine vollständige View-Datei unter `App/Views/<Name>View.swift` mit:

### 1. Grundstruktur
```swift
struct <Name>View: View {
    // Stores via @EnvironmentObject (nie @StateObject für shared stores)
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var orderStore: OrderStore
    @EnvironmentObject var networkMonitor: NetworkMonitor

    // Lokaler UI-State via @State
    @State private var isLoading = false
    @State private var error: AppError? = nil

    var body: some View { ... }
}
```

### 2. Offline-Awareness (immer einbauen)
```swift
// Offline-Banner wenn nicht verbunden
if !networkMonitor.isOnline {
    OfflineBanner() // "Offline — TSE-Signatur ausstehend"
}
```

### 3. Error Handling
```swift
// Fehler immer als Alert anzeigen, nie still schlucken
.alert("Fehler", isPresented: $showError) {
    Button("OK") { error = nil }
} message: {
    Text(error?.localizedDescription ?? "Unbekannter Fehler")
}
```

### 4. Loading States
```swift
// Async-Operationen immer mit isLoading absichern
Button("Bezahlen") {
    Task {
        isLoading = true
        defer { isLoading = false }
        do {
            try await orderStore.pay(...)
        } catch {
            self.error = error as? AppError
        }
    }
}
.disabled(isLoading)
```

### 5. iPad-Optimierung
- `NavigationSplitView` für Master-Detail-Layouts
- Mindest-Touch-Target: 44×44pt
- Landscape-first (iPad wird quer gehalten im Betrieb)
- Kein `NavigationView` (deprecated)

### 6. Deaktivierte Features (nicht implementieren)
- Kein Trinkgeld-UI (Phase 3+)
- Kein Außer-Haus-Toggle aktiv (Phase 4+)
- Kein Drucker/PrinterManager (Phase 5+)

### 7. Preview
```swift
#Preview {
    <Name>View()
        .environmentObject(AuthStore.preview)
        .environmentObject(OrderStore.preview)
        .environmentObject(NetworkMonitor.preview)
}
```

### Stores und wann welcher gebraucht wird
| Store | Wann |
|-------|------|
| `AuthStore` | User-Info, Logout, Permissions |
| `OrderStore` | Bestellungen, Tischstatus, Items |
| `SessionStore` | Kassensitzung offen/geschlossen |
| `SyncManager` | Offline-Queue-Status anzeigen |
| `NetworkMonitor` | isOnline, immer einbinden |

**Format der Eingabe:** Beschreibe die View, z.B.:
"OrderView — zeigt offene Bestellung für einen Tisch, Produktgitter, Warenkorb"
"ModifierSheet — Bottom Sheet für Produktvarianten-Auswahl mit Pflichtauswahl-Validierung"
"SessionView — Kassensitzung öffnen/schließen mit Bargeld-Eingabe"

# Kassensystem SaaS — Claude-Kontext

## Projekt
iPad-basiertes Kassensystem für Gastronomie (Shishabar, Café, Späti) als SaaS.
Pilotkunde: Shishabar (Freund, kostenlos gegen Feedback + Referenz).

**Stack:** Node.js / TypeScript / Express / MariaDB / Fiskaly (Cloud-TSE) / Stripe / SwiftUI
**Vollständiger Plan:** `implementierungsplan.md`
**Entwickler:** Niko — solide Node.js/TS/MariaDB-Erfahrung, SwiftUI neu

---

## Aktueller Stand

**Phase:** Phase 1 + Phase 2 Frontend vollständig ✅ — Pilot-Testing bereit
**Suiten:** Backend 139 Unit/Compliance + 354 Integration, iOS 71 XCTests — alle grün (2026-07-21)
**Alle offenen Punkte + Priorisierung:** `OFFEN.md` (einzige Quelle — Backend, Frontend, Tests, Infra, Recht)
**Abarbeitungsreihenfolge bis Go-live:** `ROADMAP.md` — ein Paket pro Session, jedes Paket hat dort einen fertigen Session-Prompt + Definition of Done. Beim Start einer Session mit Paket-Auftrag („Setze Paket Sxx um") zuerst ROADMAP.md lesen.

**Bekannte offene Sicherheitslücken:** keine ✅ (Audit #1 + Finanz-Integritäts-Audit #2, beide 2026-07-10: alle kritischen Findings behoben — u.a. Doppel-Storno-Race, Session-Close-Race, cancelOrder-Guard, app_user-DELETE-Grant. Details + verbleibende mittlere Punkte: `OFFEN.md` §1)

**Betriebshinweis:** Berichte nutzen `CONVERT_TZ(…, 'Europe/Berlin')` — der Produktions-MariaDB-Server braucht geladene Timezone-Tabellen (`mariadb-tzinfo-to-sql /usr/share/zoneinfo | mysql mysql`), sonst liefern alle Berichte 0.

**Pilot-Ziel:** Shishabar-Test — kein festes Datum

---

## Pflicht bei jeder Änderung (Code, Fix, Refactor)

Nach **jeder** Änderung — egal ob über Skill oder direkt — folgendes prüfen:
- Steht der Punkt unter "Aktueller Stand → Bekannte offene Sicherheitslücken"? → entfernen
- Ist der Punkt in `OFFEN.md` gelistet? → streichen (erledigt) oder Prio/Beschreibung anpassen
- Neue offene Punkte (Bugs, Schulden, Ideen) → nur in `OFFEN.md` eintragen, mit Prio + Warum

## Pflicht bei jeder Implementierung

Nach jeder Implementierung (neue Route, neuer Controller, neue Funktion) **immer** den Abschnitt "Implementierungsstand Backend" in dieser Datei aktualisieren:
- ✅ setzen sobald ein Endpoint vollständig implementiert und getestet ist
- ❌ entfernen oder korrigieren wenn eine Annahme falsch war
- Neue Endpoints sofort mit ❌ eintragen, damit sie nicht als "vergessen" gelten

**Warum:** Ohne aktuellen Stand liest Claude neue Controller-Dateien und schlußfolgert fälschlicherweise, dass zugehörige Endpoints fehlen — obwohl sie z.B. in einer anderen Route eingebunden sind (Beispiel: `paymentsController` hängt an `POST /orders/:id/pay`, NICHT an einem eigenen `/payments`-Endpoint).

Dasselbe gilt für das **Frontend (SwiftUI):** Nach jeder Implementierung (neuer Screen, neue View, neuer Store, neue Funktion) **immer** den Abschnitt "Implementierungsstand SwiftUI Frontend" in dieser Datei aktualisieren — ✅ wenn Screen/File fertig ist, ❌ bei noch offenen Punkten oder falschen Annahmen.

---

## KRITISCHE REGELN — nie brechen

### Geld
- Alle Geldbeträge **immer als Integer (Cent)** — niemals Float oder Decimal
- Variablennamen: `price_cents`, `amount_cents`, `subtotal_cents` — nie `price` oder `amount` allein
- Rechnung: `(product_price_cents + SUM(modifier_delta_cents)) × quantity - discount_cents`

### Finanzdaten (GoBD — gesetzliche Pflicht)
- **KEIN DELETE** auf diesen Tabellen (niemals, auch nicht in Tests/Migrations):
  `orders`, `order_items`, `receipts`, `payments`, `cancellations`,
  `audit_log`, `z_reports`, `product_price_history`, `order_item_modifiers`, `order_item_removals`
- **KEIN UPDATE auf Finanzdaten** (Beträge, Positionen, Steuern) — diese Felder sind nach dem INSERT unveränderlich
- **Erlaubte UPDATEs** (operative Zustandsfelder, keine Buchungsdaten):
  - `orders.status` (`open` → `paid` / `cancelled`) und `orders.closed_at`
  - `cash_register_sessions.status`, `.closed_at`, `.closing_cash_cents`, `.expected_cash_cents`, `.difference_cents`
  - `offline_queue.status`, `.retry_count`, `.error_message`, `.synced_at`, `.payload_json`, `.processing_started_at`
  - `tse_outages.ended_at`, `.notified_at`, `.reported_to_finanzamt`
  - `email_queue.status`, `.attempts`, `.next_attempt_at`, `.last_error`, `.processing_started_at`,
    `.sent_at` sowie das Nullen von `.subject`/`.body_html`/`.body_text` nach Erfolg (DSGVO).
    **`email_log` dagegen ist INSERT-only** (Versandnachweis, via `audit_insert_user`)
  - `receipts.tse_*` + `.tse_pending` (nur Nachsignierung via Offline-Queue — keine Beträge)
  - `products.price_cents` / `.vat_rate_*` (nur in `changePrice` NACH dem `product_price_history`-INSERT)
- Storno = neue Gegenbuchung in `cancellations` + neue TSE-Transaktion, nicht Zeile ändern.
  **Storno-Bon trägt negierte Beträge** (`vat_*`, `total_gross_cents`) **+ negative `payments`-Zeilen** je Original-Zahlungsmittel — so netten alle `SUM()`-Aggregationen (Berichte, Z-Bericht, Kassenbestand) automatisch aus. Items im `raw_receipt_json` bleiben der positive Original-Snapshot.
- Preisänderung **nur** über `POST /products/:id/price`: schreibt zuerst den GoBD-Pflicht-Eintrag in `product_price_history` (INSERT-only via auditDb), danach `UPDATE products SET price_cents` (operativer Preis — addItem/listProducts lesen diese Spalte). Direktes `price_cents` via `PATCH /products/:id` bleibt verboten (Route-Guard).
- **Order-Item entfernen** = `INSERT INTO order_item_removals` (wer, wann, warum) — `order_items`-Zeile bleibt erhalten; Queries filtern via `NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`
- Bon-Nummer vergeben → TX schlägt fehl → Receipt mit `status='voided'` anlegen, niemals skippen
- **Session-Lock-Invariante (Audit #2):** `payOrder`, `splitBill` und `cancelReceipt` sperren in ihrer TX die `cash_register_sessions`-Zeile (`FOR UPDATE`) und geben 409, wenn sie nicht mehr `open` ist; `closeSession` läuft komplett in einer TX unter demselben Lock (Aggregation + Schließen). So kann kein Bon in eine geschlossene Session buchen und im unveränderlichen Z-Bericht fehlen. **Jeder neue Buchungspfad muss dieses Lock übernehmen.** Lock-Reihenfolge: Order/Receipt → Session → receipt_sequences (Deadlock-Vermeidung)
- **Doppel-Storno:** `cancellations.original_receipt_id` ist UNIQUE (V008) — Controller prüft zusätzlich unter FOR-UPDATE-Lock auf dem Original-Bon

### Tenant-Isolation
- **Jede** DB-Query enthält `WHERE tenant_id = ?` — keine Ausnahme
- `tenant_id` kommt **immer** aus JWT via `tenantMiddleware`, nie aus Request-Body oder URL-Params
- Bei Zweifeln: 404 zurückgeben statt falsche Daten

### Validierung
- Jede Route braucht ein Zod-Schema via `validationMiddleware(schema)`
- Kein `req.body.irgendwas` ohne vorherige Zod-Validierung
- Alle Enum-Felder als Zod-Whitelist definieren
- **Query-Params (GET-Routen):** `validationMiddleware` validiert nur `req.body` — Query-Params direkt im Controller via `schema.safeParse(req.query)` validieren

### Bon / Receipts
- `raw_receipt_json` wird **nur einmal** geschrieben (bei `status='active'`), danach kein UPDATE
- `receipt_number` kommt **ausschließlich** aus `receipt_sequences` via `SELECT ... FOR UPDATE`
- `receipts.device_id` und `receipts.device_name` sind NOT NULL — immer befüllen
- `receipts.device_name` ist ein Snapshot (zum Zeitpunkt des Bons), nicht der aktuelle Name

### Testing
- Neue Berechnungslogik → Unit Test (kein Merge ohne)
- Neue Route → Integrationstest + Tenant-Isolation-Test
- Compliance-Tests sind niemals optional

---

## Deaktivierte Features — nicht implementieren bis Phase freigegeben

| Feature | Aktiv ab | Grund |
|---------|----------|-------|
| Trinkgeld (UI + Logic) | Phase 3 | Steuerberater-Klärung ausstehend |
| Außer-Haus-Toggle (UI + Logic) | Phase 4 | Steuerberater-Klärung pro Betrieb |
| Bondrucker / StarIO SDK | Phase 5 | Bewusste Scope-Entscheidung |
| Multi-iPad Sync | Phase 5 | Bewusste Scope-Entscheidung |

Felder dürfen in DB vorhanden sein (Vorbereitung), aber keine UI/Business-Logic dazu.

---

## Middleware-Reihenfolge (Express — genau diese Reihenfolge)

```
rateLimitMiddleware
→ authMiddleware
→ deviceMiddleware
→ tenantMiddleware
→ subscriptionMiddleware
→ sessionMiddleware       ← nur für Order- und Payment-Routen
→ planMiddleware
→ validationMiddleware(schema)
→ handler
```

---

## DB-Berechtigungen (drei verschiedene DB-User)

```
app_user          SELECT, INSERT, UPDATE, CREATE, ALTER, INDEX (inkl. Migrations) —
                  KEIN pauschales DELETE (Audit #2): DELETE nur tabellen-scoped auf
                  Nicht-Finanztabellen (Seed-Rollback); in der Test-DB pauschal (testHelpers)
audit_insert_user NUR INSERT auf: audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals
app_readonly      SELECT only (für Reports, Admin-Panel)
```

Setup: `npm run db:setup` (development) / `npm run db:setup:test` (test)
Nie mit einem DB-User der alle Rechte hat arbeiten.

---

## Kassensitzungspflicht

Orders und Payments können nur erstellt werden wenn eine offene `cash_register_session` existiert.
`sessionMiddleware` gibt 409 zurück wenn keine Session offen.

---

## TSE / Fiskaly

### Begriffe (nicht verwechseln!)
- **TSS** = eine Fiskaly-TSE-Instanz pro Tenant — wird einmalig angelegt (Phase 2, bei Registrierung)
- **TSE-Client** = Fiskaly-Objekt pro Gerät — wird einmalig angelegt (Phase 2, bei Geräte-Registrierung)
- **TSE-Transaktion** = Signatur pro Bon — läuft bei jeder Zahlung (Phase 2+)
- **ELSTER** = Finanzamt-Portal — ist **nicht** Teil des täglichen TSE-Flows; relevant nur bei: (1) neue Kasse anmelden (manuell, einmalig), (2) TSE-Ausfall >48h melden (KassenSichV-Pflicht)
- **DSFinV-K** = Export auf Anfrage des Finanzamts (Betriebsprüfung) — kein Alltagsbetrieb

### Phase 1 vs. Phase 2
- **Phase 1 (aktuell):** Fiskaly wird gar nicht aufgerufen. `tenants.fiskaly_tss_id = NULL`, `devices.tse_client_id = NULL`. Bons haben keine TSE-Felder. Für Piloten-Betrieb okay, muss vor Go-live umgestellt werden.
- **Phase 2:** TSS anlegen bei `POST /onboarding/register`, TSE-Client anlegen bei `POST /devices/register`.

### API-Regeln
- Jede TSE-Operation braucht einen `idempotency_key` (UUID) in `offline_queue`
- Bei Timeout: GET /tx/{tx_id} prüfen bevor neuer Request gesendet wird
- TSE-Transaktionen laufen immer mit `client_id = device.tse_client_id`
- Geldbeträge an Fiskaly: Strings mit 2 Dezimalstellen ("30.50"), nicht Cent-Integer
- API-Felder: `amounts_per_vat_rate` und `amounts_per_payment_type` (Singular! kein trailing 's')
- Jeder `amounts_per_vat_rate`-Eintrag braucht `amount` (Brutto-String, **required**) + `excl_vat_amounts`
- Das vollständige Schema muss bei **jedem** PUT mitgeschickt werden — auch beim FINISHED-Request

---

## Phasenplan (Überblick)

Vollständiger Plan mit Deliverables, Priorisierung und offenen Punkten: **`implementierungsplan.md` §15–18**

| Phase | Backend | SwiftUI |
|-------|---------|---------|
| 1 | ✅ Auth, Produkte, Tische, Bestellungen, Kassensitzungen | ⏳ LoginView ✅, alle anderen Screens ❌ |
| 2 | ✅ TSE, Receipts, Split Bill, Z-Bericht | ❌ PaymentView, ReceiptView |
| 3 | ✅ Stripe, Onboarding, Offline-Queue | ❌ SyncManager |
| 4 | ✅ DSFinV-K Export, Berichte | ❌ BerichteView, Admin-Panel |
| 5 | ❌ Bondrucker, Multi-iPad, DATEV | ❌ |

---

## Testing-Befehle

```bash
npm test                     # unit + compliance (< 30s)
npm run test:integration     # echte MariaDB Test-DB (< 2min)
npm run test:external        # Fiskaly Sandbox + Stripe (nightly)
npm run test:coverage        # Coverage-Report
```

**CI (PR-Gate):** `.github/workflows/ci.yml` fährt bei jedem PR/Push auf `main` zwei Jobs — `backend`
(`tsc --noEmit` + `npm test` + `test:integration` gegen einen MariaDB-Service-Container) und `ios`
(`xcodebuild test` auf `macos-26`, Simulator dynamisch gewählt). Beide sind Required Status Checks,
rote Suite = nicht mergebar, `main` ist gegen Direkt-Pushes geschützt. Details, Branch Protection und
die CI-Stolpersteine (Grant-Host, Timezone-Tabellen, Port-Mapping, geteiltes Xcode-Scheme):
`docs/ci.md`. `scripts/setup-db.ts` versteht dafür `DB_USER_HOST` (Default `localhost`, in CI `%`).
Das Xcode-Scheme muss **shared** bleiben (`xcshareddata/xcschemes/`) — `xcuserdata/` ist gitignored.

---

## Implementierungsstand Backend

### Fertig implementiert ✅
| Bereich | Endpoints | Tests |
|---------|-----------|-------|
| Auth | POST /auth/login, /refresh, /logout, /pin | ✅ |
| Tenants | GET+PATCH /tenants/me | ✅ |
| Users | GET /users, POST, PATCH /:id, DELETE /:id (soft) | ✅ |
| Devices | POST /devices/register, /:id/revoke, GET / | ✅ |
| Products | GET /products (`?include_inactive=1` = Management-Ansicht; Default = Kasse, nur aktive), POST /products (persistiert `sort_order`, Default MAX+10 je Kategorie), PATCH+DELETE /:id, GET+POST+PATCH+DELETE /products/categories | ✅ |
| Sortiment-Reorder | PATCH /products/reorder + PATCH /products/categories/reorder (komplette geordnete ID-Liste, TX, tenant-verifiziert 404, owner/manager) — S17A | ✅ |
| Starter-Presets | GET /products/presets (alle Rollen) + POST /products/presets/import (owner/manager, Idempotency-Key-Header, Pfand-Gate, Review-Pflicht, Bulk-Plan-Limit) — S17B, Vertrag: `docs/api.md`. **Produkt-Anlage läuft app-weit über `services/products.ts → createProductWithHistory`** (inaktiv → Historie → Verify → aktiv; kein zweiter INSERT-Pfad!) | ✅ |
| Preisänderung | POST /products/:id/price (→ product_price_history, GoBD) | ✅ |
| Modifier Groups | CRUD /modifier-groups + /options | ✅ |
| Tische/Zonen | CRUD /tables + /zones | ✅ |
| Kassensitzungen | open, close (+ Z-Bericht), current, /:id, /:id/z-report, movements | ✅ |
| Bestellungen | GET+POST /orders, GET /:id (liefert bei `paid` einen `receipt`-Block im PaymentResult-Shape — A4-Recovery), items (add/remove), cancel, pay, pay/split | ✅ |
| Bons | GET /receipts (Liste), GET /receipts/:id, POST /:id/cancel | ✅ |
| Offline-Sync | GET+POST /sync/offline-queue | ✅ |
| Onboarding | POST /onboarding/register, POST /onboarding/create-checkout-session | ✅ |
| Stripe Webhook | POST /webhooks/stripe (alle Subscription-Events, Idempotenz) | ✅ |
| Berichte | GET /reports/daily, GET /reports/summary (Plan-Limit: 30/365/3650 Tage) | ✅ |
| DSFinV-K Export | GET /export/dsfinvk, /:exportId/status, /:exportId/file | ✅ |
| E-Mail (Resend) | **kein Endpoint** — Service `services/email/` (enqueue + drain), 6 von 6 Template-Gruppen inkl. 3 Subscription-Varianten | ✅ |

### Noch nicht implementiert ❌
| Bereich | Endpoints | Phase |
|---------|-----------|-------|
| Bon-PDF | GET /receipts/:id/pdf | Phase 5 |

---

## Implementierungsstand SwiftUI Frontend

**Design v3.1 (2026-07-11, Impeccable-Pass):** Kiosk-App — `TARGETED_DEVICE_FAMILY=2` (iPad-only, App **und** Test-Target), `IPHONEOS_DEPLOYMENT_TARGET=26.2` in allen vier Build-Configs (T7-Entscheidung 2026-07-20: nur aktuelles iPadOS ab 26 — deshalb braucht CI `macos-26`), `UIRequiresFullScreen=YES`, nur Landscape. Dynamic Type app-weit über `.dsFont(…)` (Root-Deckel AX1 in ContentView), Appearance System/Hell/Dunkel (`DSAppearance`, Default System, app-weit in ContentView angewandt — **keine per-View `preferredColorScheme` mehr außer Previews**), app-weiter `.tint(DS.C.acc)`, Anrede durchgängig Du. Fonts: `.dsFont` ist die einzige Font-API (`DS.F`/`DS.T`/`.jakarta()` gelöscht, Jakarta-TTFs entfernt).

### Fertig implementiert ✅
| Screen / File | Inhalt | Stand |
|---------------|--------|-------|
| `DesignSystem.swift` | Design v3.1 „Ledger Green": Farb-/Radius-/Spacing-/Motion-Tokens (`DS.C/R/S/M`), zentrale `euroString()`/`parseCents()` (A8: eine Implementierung, `Int?` — nil disabled Save-Buttons)/`MoneyText` (inkl. VoiceOver-Betrags-Label), Button-Styles (`DSPrimaryButton` etc.), `DSPill`, `DSEmptyState`, `DSSectionLabel`, `dsCard()`/`dsInput()` — keine Font-Statics mehr | ✅ |
| `DSComponents.swift` | v3.1-Komponenten: `.dsFont(_:)` (Dynamic-Type-Typo-Tokens via UIFontMetrics; `.money`-Tokens mit Tabellenziffern, `.mono` für Beleg-Ästhetik, `.icon`/`.raw` für Sondergrößen), `DSTextField` (das eine Eingabefeld: Label/Hint/Error/Secure-Reveal, NoAssistant-Engine), `DSSheetScaffold` (einheitliches Sheet-Chrome: Icon-Badge + xmark + Footer, `isDirty` → Dismiss-Guard), `DSSegmentedControl`, `DSSkeleton`, `DSSuccessCheckmark` (Reduce-Motion-safe), `Haptics`, `dsBannerTransition()`, `DSAppearance` | ✅ |
| `AppError.swift` | App-weite Fehlertypen (LocalizedError, deutsche Meldungen) | ✅ |
| `Models.swift` | User, AuthUser, Tenant, UserRole, SubscriptionPlan, SubscriptionStatus, AuthResponse | ✅ |
| `AuthStore.swift` | ObservableObject: Login, Register, PIN-Login, Logout, User-Cache (UserDefaults), sendet deviceToken aus Keychain | ✅ |
| `APIClient.swift` | async/await HTTP-Client: JWT im Keychain, Device-Token persistent, get/post/patch/delete, Refresh-Logic | ✅ |
| `KeychainHelper.swift` | Sicherer Token-Speicher (save/load/delete, Service: com.cashbox.app) | ✅ |
| `NetworkMonitor.swift` | NWPathMonitor Wrapper, isOnline @Published | ✅ |
| `OfflineBanner.swift` | Offline-Hinweisband; liest `pendingCount` live aus `SyncManager.shared` (zeigt „N Bons warten auf TSE-Signatur") | ✅ |
| `LoginView.swift` | 2-Spalten Login: Brand-Panel + Formular (DSTextField), PIN-Liste, Darstellungs-Umschalter (System/Hell/Dunkel), PINEntrySheet | ✅ |
| `OnboardingView.swift` | Registrierungs-Flow (6 Schritte) mit Abbrechen-X (+ Verwerfen-Rückfrage), erzwungener Pflicht-Checkliste (Schritt 5 gated `canContinue`), ehrlichem TSE-Pending-Status; Felder = exakt das Backend-Schema (vatId/Standort entfernt — registerSchema nimmt sie nicht an). Einziger Registrierungsweg (RegisterView.swift gelöscht 2026-07-10) | ✅ |
| `ContentView.swift` | Auth-Router: LoginView ↔ App; app-weite Modifier: Dynamic-Type-Deckel (AX1), `preferredColorScheme` aus `DSAppearance`, `.tint(DS.C.acc)` | ✅ |
| `zettel_frontendApp.swift` | Root mit @StateObject Stores + EnvironmentObject Injection | ✅ |
| `SessionStore.swift` | ObservableObject: Session laden/öffnen/schließen, Movements, Preview-Factories | ✅ |
| `OrderStore.swift` | ObservableObject: Orders laden, erstellen, Items add/remove, Storno, Preview-Factories | ✅ |
| `KassensitzungView.swift` | Session öffnen (Eröffnungsbestand), aktive Session mit Stats + Movements, Schicht schließen + Z-Bericht-Sheet. Live-Kassenzählung (KassenstandCard) befüllt das Abschluss-Sheet vor (State in Root); „Kasse stimmt"-Moment bei ±0 im Z-Sheet | ✅ |
| `TableStore.swift` | ObservableObject: Tischliste + Zonen laden, occupiedCount, Preview-Factories | ✅ |
| `TableOverviewView.swift` | Haupt-App-Shell: Topbar (Session-Chip, User), Sidebar (Nav + KPIs + Schnellkasse), Tischgitter 3-Spalten mit Zone-Filter-Pills, Kacheln mit Status-Badge + Streifen | ✅ |
| `ProductStore.swift` | ObservableObject: `loadProducts(includeInactive:)` (Sortiment = true, Kasse = Default false; Ergebnis via `assortmentSorted`), `products(for:)` filtert IMMER auf aktiv (Kassen-Verteidigungslinie), CRUD für Produkte + Kategorien inkl. GoBD-Preisänderung, `reorderProducts`/`reorderCategories` (S17A), Preview-Factories | ✅ |
| `OrderView.swift` | Produktkatalog (links: Kategorie-Pills, 3-Spalten-Grid) + Warenkorb-Panel (rechts: Items, Total, Bezahlen). ModifierSelectionSheet für Pflicht-Modifier integriert. Öffnet PaymentView nach "Bezahlen". | ✅ |
| `PaymentView.swift` | Bar / Karte / Gemischt, MwSt-Aufschlüsselung (7%/19%), POST /orders/:id/pay, ReceiptSummarySheet (Erfolgs-Checkmark + Haptik). Bar: Betrag mit „passend" vorbelegt (Prefill, erste Eingabe ersetzt). **Karte: ehrlicher 2-Schritt** — „Terminal hat die Zahlung genehmigt"-Bestätigung gated den Erfassen-Button (Phase 1 hat keine Terminal-Integration; kein Fake-„Warte auf Terminal"). **A4-Recovery:** 409/Timeout → `OrderStore.recoverPayment` lädt den Order-Status nach; `paid` → Bon-Sheet statt Sackgassen-Alert | ✅ |
| `PaymentLogic.swift` | Pure Zahlungs-/MwSt-Logik, aus PaymentView extrahiert für Testbarkeit: `computeVat` (Formelparität mit Backend-calcVat), `buildPayments(mode:barRaw:totalCents:)` (Summen-Invariante == total; Gemischt bar>total wird geklemmt) | ✅ |
| `ReportStore.swift` | ObservableObject: Tagesbericht (GET /reports/daily), Zusammenfassung (GET /reports/summary), Preview-Factories | ✅ |
| `UsersStore.swift` | ObservableObject: User laden/erstellen/bearbeiten/löschen (soft-delete), Preview-Factories | ✅ |
| `ReceiptView.swift` | Compliance-Bon (KassenSichV + GoBD + §14 UStG): 2-Spalten (Bon-Details links, TSE + QR-Code rechts), Tenant-Snapshot, Positionen, MwSt, TSE-Pending-Hinweis | ✅ |
| `ZBerichtView.swift` | Z-Bericht aus lastZReport (SessionStore), KPI-Kacheln, Kassenbestand mit Differenzanzeige, Empty-State | ✅ |
| `BerichteView.swift` | Täglich/Zeitraum-Tab, Datumsnavigation, KPI-Kacheln, Sessionsliste, MwSt-Aufschlüsselung, Quick-Buttons (7/30 Tage) | ✅ |
| `SortimentView.swift` | S17A: EIN Bereich für Produkte + Kategorien (ersetzt ProdukteView + KategorienView, beide gelöscht 2026-07-21). Kategorienleiste links (Inline-Anlage, Kontextmenü Bearbeiten/Löschen), rechts Kassenansicht (ProductCard-Kacheln) / Liste, Suche, Aktiv/Inaktiv-Filter, Reihenfolge-Sheet (native List + `.onMove`), Quick-Create (Name+Preis+Kategorie, „Weitere Einstellungen" progressiv), Edit-Sheet mit GoBD-Preispfad, Löschtext == Backend-409-Verhalten | ✅ |
| `ProductCard.swift` | Die Kassenkachel, aus OrderView extrahiert (`OProductCard` → `ProductCard`, internal) — OrderView (Kasse) und SortimentView (Vorschau) rendern exakt dieselbe Komponente; `dimmed`-Zustand + „Inaktiv"-Pill fürs Management; optionaler Visual-Slot (S17B: Kategorie-Tint, `accessibilityHidden`) | ✅ |
| `SortimentWizardView.swift` | S17B: 8-Schritte-Wizard (Paket → Auswahl → Namen&Preise → MwSt. → Visuals → Vorschau → Import → Ergebnis) nach OnboardingView-Muster; Pfand-/Vorlagen-Sperren, Sammel- vs. Einzelbestätigung (`WizardReviewState`), ein UUID-Idempotency-Key pro Import-Serie, `VisualPickerSheet` (39 Keys + „Ohne Symbol") | ✅ |
| `ProduktVisualCatalog.swift` | 39 semantische Keys → SF Symbols/4 Bundle-Assets (`product.shisha`, `.shisha.refill`, `.croissant`, `.pretzel` — eigene monochrome Template-PDFs), generic-Fallback für unbekannte Keys/fehlende Assets, lokalisierte Labels, `ProductVisualView` | ✅ |
| `VisualSuggestion.swift` | Namensheuristik (§6.4): Ganze-Wort-Matching nach Normalisierung (Diakritika, ß→ss, Mengenangaben), spezifischste Regel zuerst, Kategorie sekundär, kein Treffer ⇒ nil — nur Picker-Vorbelegung | ✅ |
| `PresetModels.swift` | Decodables für GET /products/presets + Import-Vertrag (visual_key als String? — zukunftstolerant), `WizardReviewState` (pure, getestet) | ✅ |
| `EinstellungenView.swift` | Betriebsdaten (GET/PATCH /tenants/me), Tischverwaltung (Tab "Tische"), Mitarbeiterverwaltung (CRUD via UsersStore), UserFormSheet, Soft-Delete-Bestätigung | ✅ |
| `TischverwaltungView.swift` | Tische & Zonen verwalten: Liste, ZoneFormSheet, TischFormSheet (Zone-Picker), Deaktivieren-Confirm, CRUD via TableStore | ✅ |
| `zettel-frontendTests/` (XCTest-Target) | 71 Tests: ParseCents (Locale/Rundung/Tausenderpunkt), EuroString (inkl. Roundtrip), PaymentLogic (buildPayments-Summeninvariante, Gemischt-Kanten), VatBreakdown (Formelparität mit Backend-vatCalculation.test.ts), ModelDecoding (wörtliche snake_case-Fixtures via `JSONDecoder.cashbox`, inkl. A4-receipt-Block + S17A-sort_order-Fixtures), AssortmentSort (Komparator == Backend-SQL), PresetDecoding (Wire-Format, unbekannte Keys tolerant), VisualCatalog (39 Keys exhaustiv, Fallbacks, Assets), VisualSuggestion (alle V1-Namen + Negativfälle), WizardReviewState (Sammel deckt Risikozeilen nicht). Lauf: `xcodebuild test -project zettel-frontend.xcodeproj -scheme zettel-frontend -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'` | ✅ |
| `SyncManager.swift` | Minimaler Offline-Queue-Trigger: POST /sync/offline-queue bei Online-Wechsel/Foreground/Login (max. 3 Runden), pendingCount @Published. `SyncManager.shared` — dieselbe Instanz wird als EnvironmentObject injiziert und vom OfflineBanner direkt gelesen. Vollausbau Phase 3 | ✅ |

### Noch nicht implementiert ❌ (SwiftUI)
| Screen | Abhängigkeiten | Phase |
|--------|----------------|-------|
| Bon-PDF senden | GET /receipts/:id/pdf + ShareSheet | Phase 5 |
| SyncManager Vollausbau | Retry-UI, Fehler-Detailansicht | Phase 3 |

### Offene Punkte (SwiftUI + Backend)
**→ `OFFEN.md`** — einzige Quelle, hier keine Doppelpflege. Implementiert-Hinweise, die beim Codelesen helfen:
- Token-Refresh ✅: APIClient refresht bei 401 automatisch und wiederholt den Request; Force-Logout erst wenn Refresh scheitert
- SyncManager (minimal) ✅: triggert POST /sync/offline-queue bei Online-Wechsel/Foreground/Login, hält pendingCount — Vollausbau (Retry-UI) ist Phase 3, siehe OFFEN.md

### Backend — Logging (implementiert ✅)
- **Pino** (`pino` + `pino-http`) — JSON-Logs in Production, Pretty-Print in Development
- `src/logger.ts` — zentraler Logger, via `LOG_LEVEL` env konfigurierbar (default: `info`)
- Jeder Request loggt: `method`, `url`, `status`, `responseTime`, `tenant` (aus JWT)
- 4xx → `warn`, 5xx → `error`, 2xx → `info` — `/health` wird nicht geloggt
- Globaler Error Handler nutzt `logger.error` statt `console.error`

### Backend — Monitoring & Shutdown (implementiert ✅, Details `docs/betrieb.md`)
- **Sentry** (`src/sentry.ts`, `@sentry/node` v10) — `captureException` im globalen Error-Handler.
  **Nur 5xx** wird gemeldet (4xx = Normalbetrieb: falscher PIN, 409, 422), Kontext ist
  `tenant` (aus JWT), `method`, `url`. **Keine PII**: keine Bodies, Header, IPs, Namen oder
  Beträge (`sendDefaultPii: false`, kein Tracing) — AVV-relevant, beim Erweitern prüfen.
  Ohne `SENTRY_DSN` ist Sentry komplett aus und alle Aufrufe sind No-Ops.
  `src/sentry.ts` **muss der erste Import in `index.ts` bleiben** (lädt eigene .env —
  mit demselben `NODE_ENV`-Pfad-Switch wie `db/index.ts`, sonst meldet der Testlauf
  echte Events ans Produktionsprojekt; Regressionsschutz: `unit/sentryConfig.test.ts`).
- **Shutdown** (`src/shutdown.ts`) — Reihenfolge **Server drainen → Sentry flushen →
  DB-Pools schließen → exit**, idempotent gegen ein zweites Signal, 10-s-Notbremse bei
  hängendem Drain. Ausgelöst von SIGTERM/SIGINT sowie `unhandledRejection`/
  `uncaughtException` (Exit 1). `closeIdleConnections()` ist Pflicht — iPads halten
  Keep-Alive-Sockets offen, sonst läuft jeder Deploy in die Notbremse.
  Prozess-Manager braucht ≥ 15 s Kulanz (PM2 `kill_timeout`, systemd `TimeoutStopSec`).

### Auth — kritische Backend-Details
- **Token-Modell:** Access-JWT 15 min (`JWT_EXPIRY`), Refresh-Token 7 d rotierend (`JWT_REFRESH_EXPIRY`), **absolutes Session-Limit 16 h** (`SESSION_MAX_HOURS`, Schicht-Modell: 1× Login pro Tag). `session_start`-Claim im Refresh-Token wird bei Rotation unverändert weitergereicht; `/auth/refresh` gibt 401 wenn Limit überschritten oder Claim fehlt, Token-`exp` ist zusätzlich auf `session_start + Limit` gedeckelt. iOS zeigt danach automatisch das „Sitzung abgelaufen"-Banner (forceLogout)
- `POST /auth/login` erwartet **auch `device_token`** — Gerät muss registriert sein (via `/onboarding/register` oder `/devices/register`)
- Login/Register-Response: `{token, refreshToken, user: {id, name, role}}` — **kein `tenant`-Objekt**
- iOS-Modell `AuthUser` ist deshalb schlanker als `User` (nur id, name, role)
- iOS `AuthStore.login()` sendet `deviceToken` aus Keychain mit

---

## Projektstruktur Backend

```
scripts/
└── setup-db.ts         -- DB + User + Grants + Migrations (dev/test)
src/
├── app.ts
├── index.ts           -- Start, Signal-Handler, Prozess-Ende (sentry.js zuerst importieren!)
├── sentry.ts          -- Error-Monitoring (No-Op ohne SENTRY_DSN)
├── shutdown.ts        -- createShutdown(): Drain → Flush → Pools (pure, DI-testbar)
├── routes/             -- auth, devices, export, modifierGroups, onboarding, orders,
│                          products, receipts, reports, sessions, sync, tables,
│                          tenants, users, webhooks
├── controllers/        -- authController, cancellationsController,
│                          devicesController, exportController,
│                          modifierGroupsController, offlineQueueController,
│                          onboardingController, ordersController,
│                          paymentsController (in orders-Route eingebunden),
│                          productsController, receiptsController,
│                          reportsController, sessionsController,
│                          splitBillController, tablesController,
│                          tenantsController, usersController, webhookController
│
│   HINWEIS: paymentsController ist unter POST /orders/:id/pay eingebunden,
│            NICHT als eigene /payments-Route.
│            splitBillController ist unter POST /orders/:id/pay/split eingebunden.
│            Z-Bericht wird in sessionsController.closeSession generiert —
│            KEINE eigene Route/Controller nötig.
│            webhookController liegt unter POST /webhooks/stripe (kein authMiddleware,
│            rawBody als Buffer aus express.raw() in app.ts).
│
├── middleware/         -- authMiddleware, deviceMiddleware, planMiddleware,
│                          rateLimitMiddleware, sessionMiddleware,
│                          subscriptionMiddleware, tenantMiddleware,
│                          validationMiddleware
├── services/
│   ├── audit.ts        -- audit_log INSERT via audit_insert_user
│   ├── email/          -- E-Mail (Resend via REST, kein SDK):
│   │                      index.ts   = öffentliche Anlass-Funktionen für Trial, TSE-Ausfall,
│   │                                   Passwort-Reset, Z-Bericht, Abo-Status und Langzeit-Session
│   │                      queue.ts   = enqueueMail (INSERT IGNORE auf idempotency_key)
│   │                                   + drainEmailQueue (Claim, Backoff, email_log)
│   │                      send.ts    = Resend-Call, Dry-Run ohne RESEND_API_KEY
│   │                      templates.ts / layout.ts / palette.ts / format.ts
│   │                      HINWEIS: drainEmailQueue ruft bisher NIEMAND periodisch auf —
│   │                               der Cron-Drain kommt in S07.
│   ├── fiskaly.ts      -- TSE-Operationen + Offline-Fallback (enqueueOffline);
│   │                      10s-Timeout je Request; befüllt tse_outages
│   │                      (Offline-Fallback öffnet, Erfolg schließt Eintrag)
│   ├── priceHistory.ts -- product_price_history INSERT
│   ├── products.ts     -- createProductWithHistory: DER Produktanlage-Pfad (S17B) —
│   │                      inaktiv → Historie (auditDb) → Verify → aktivieren;
│   │                      Origin-Retry repariert, reaktiviert nie Betreiber-Deaktiviertes
│   ├── presets/        -- presetTypes.ts (VISUAL_KEYS-Whitelist 39, VatReview,
│   │                      COLOR_ROLE_HEX) + presetData.ts (shisha_bar@1, cafe@1,
│   │                      spaeti@1, empty@1 — wörtlich aus docs/s17-sortiment-starterpakete.md)
│   ├── receipts.ts     -- Bon-Generierung + Pflichtfeld-Prüfung
│   └── sequences.ts    -- receipt_sequences FOR UPDATE
├── db/
│   ├── migrations/     -- V001__initial_schema, V002__order_items_soft_delete,
│   │                      V003__onboarding_trial_stripe, V004__tenants_subscription_period_end,
│   │                      V005__shishabar_seed (Pilot-Testdaten: Tenant, Users, Produkte, Tische),
│   │                      V006__offline_queue_processing_started_at (atomarer Sync-Claim),
│   │                      V007__performance_indexes,
│   │                      V008__cancellations_unique_original (Doppel-Storno-Backstop),
│   │                      V009__email_queue_and_log (email_queue operativ,
│   │                        email_log INSERT-only = Versandnachweis),
│   │                      V010__products_sort_order (persistente Kassen-Reihenfolge),
│   │                      V011__visual_key_preset_origin (visual_key, origin_* +
│   │                        UNIQUE je Tenant, preset_imports = Idempotenz-Anker)
│   ├── migrate.ts
│   └── index.ts
└── __tests__/
    ├── unit/           -- shutdown (createShutdown: Reihenfolge/Idempotenz/Notbremse),
    │                      vatCalculation, splitPartition (validateSplitPartition),
    │                      cancellationNegation (buildCancellationValues),
    │                      zReportAggregation (buildZReportData, Mock-Executor),
    │                      sequences (Mock-Conn), fiskalyPayload (centsToFiskaly,
    │                      buildAmountsPerVatRate, aggregatePaymentTypes),
    │                      emailTemplates (6 Gruppen, Subscription-Varianten,
    │                      euroString-Parität, Berlin-Zeit, esc,
    │                      Registry-Vollständigkeit, backoffMinutes),
    │                      sentryConfig (Testlauf meldet nichts — T10-Regression),
    │                      presetData (V1-Counts, Eindeutigkeit, MwSt.-Leitplanken,
    │                      Pfand exakt 11 — S17B)
    ├── integration/    -- auth, cancellations, concurrency (Promise.all-Races),
    │                      devices, e2e-tagesablauf (kompletter Kassentag),
    │                      email-queue (Enqueue/Idempotenz, Drain, email_log-Nachweis,
    │                      Retry + failed, Stuck-Claim, Tenant-Isolation),
    │                      errorHandler (5xx→Sentry, 4xx nicht, kein Leak in Prod),
    │                      export, mixed-payments, modifierGroups, offline-queue,
    │                      onboarding, orders, payments, presets (Import-Idempotenz,
    │                      Failure-Injection/Repair, Pfand-Gate, gehärteter POST),
    │                      products, receipts,
    │                      receipts-list, reports, sessions, split-bill,
    │                      stripe-webhooks, tables, tenants, users
    │                   -- Tenant-Isolation-Tests sind in jeder dieser Dateien
    │                      als eigene it()-Blöcke enthalten
    ├── compliance/     -- receipt-fields (KassenSichV + GoBD Pflichtfelder)
    └── external/       -- fiskaly (Sandbox, nightly)
```

**Testkonzept (REQ → UC → TC, Traceability-Matrix): `docs/testkonzept.md`** — neue
Anforderungen/Regeln dort als REQ eintragen, jeder REQ braucht ≥ 1 TC.
Für Unit-Tests sind die betroffenen Geld-Funktionen als pure Funktionen exportiert
(validateSplitPartition, buildCancellationValues, buildZReportData, buildAmountsPerVatRate) —
neue Geld-Logik demselben Muster folgen lassen: pure Funktion + Unit-Test, Handler ruft auf.

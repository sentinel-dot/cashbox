# Kassensystem SaaS — Claude-Kontext

## Projekt
iPad-basiertes Kassensystem für Gastronomie (Shishabar, Café, Späti) als SaaS.
Pilotkunde: Shishabar (Freund, kostenlos gegen Feedback + Referenz).

**Stack:** Node.js / TypeScript / Express / MariaDB / Fiskaly (Cloud-TSE) / Stripe / SwiftUI
**Vollständiger Plan:** `implementierungsplan.md`
**Entwickler:** Niko — solide Node.js/TS/MariaDB-Erfahrung, SwiftUI neu

---

## Pflicht bei jeder Implementierung

Nach jeder Implementierung (neue Route, neuer Controller, neue Funktion) **immer** den Abschnitt "Implementierungsstand Backend" in dieser Datei aktualisieren:
- ✅ setzen sobald ein Endpoint vollständig implementiert und getestet ist
- ❌ entfernen oder korrigieren wenn eine Annahme falsch war
- Neue Endpoints sofort mit ❌ eintragen, damit sie nicht als "vergessen" gelten

**Warum:** Ohne aktuellen Stand liest Claude neue Controller-Dateien und schlußfolgert fälschlicherweise, dass zugehörige Endpoints fehlen — obwohl sie z.B. in einer anderen Route eingebunden sind (Beispiel: `paymentsController` hängt an `POST /orders/:id/pay`, NICHT an einem eigenen `/payments`-Endpoint).

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
  - `offline_queue.status`, `.retry_count`, `.error_message`, `.synced_at`, `.payload_json`
  - `tse_outages.ended_at`, `.notified_at`, `.reported_to_finanzamt`
- Storno = neue Gegenbuchung in `cancellations` + neue TSE-Transaktion, nicht Zeile ändern
- Preisänderung = neuer Eintrag in `product_price_history`, **nie** `UPDATE products SET price_cents`; Route: `POST /products/:id/price`
- **Order-Item entfernen** = `INSERT INTO order_item_removals` (wer, wann, warum) — `order_items`-Zeile bleibt erhalten; Queries filtern via `NOT EXISTS (SELECT 1 FROM order_item_removals r WHERE r.order_item_id = oi.id)`
- Bon-Nummer vergeben → TX schlägt fehl → Receipt mit `status='voided'` anlegen, niemals skippen

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
app_user          SELECT, INSERT, UPDATE, CREATE, ALTER auf Standard-Tabellen (inkl. Migrations)
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

| Phase | Was | Besonderheit |
|-------|-----|--------------|
| 0 | Vorbereitung | Fiskaly Sandbox, SwiftUI lernen, Steuerberater, AGB |
| 1 | Backend MVP + SwiftUI ohne TSE | DSFinV-K-Datenmodell bereits kompatibel |
| 2 | TSE + Receipts + Split Bill + Z-Bericht | Erster TSE-konformer digitaler Bon |
| 3 | Stripe + Onboarding + Offline-Queue + Pilot | Produktiveinsatz Shishabar |
| 4 | DSFinV-K Export + Admin-Panel | Erste zahlende Kunden |
| 5 | Drucker + Multi-iPad + DATEV | Skalierung |

---

## Testing-Befehle

```bash
npm test                     # unit + compliance (< 30s)
npm run test:integration     # echte MariaDB Test-DB (< 2min)
npm run test:external        # Fiskaly Sandbox + Stripe (nightly)
npm run test:coverage        # Coverage-Report
```

---

## Implementierungsstand Backend

### Fertig implementiert ✅
| Bereich | Endpoints | Tests |
|---------|-----------|-------|
| Auth | POST /auth/login, /refresh, /logout, /pin | ✅ |
| Tenants | GET+PATCH /tenants/me | ✅ |
| Users | GET /users, POST, PATCH /:id, DELETE /:id (soft) | ✅ |
| Devices | POST /devices/register, /:id/revoke, GET / | ✅ |
| Products | GET+POST /products, PATCH+DELETE /:id, GET+POST+PATCH+DELETE /products/categories | ✅ |
| Preisänderung | POST /products/:id/price (→ product_price_history, GoBD) | ✅ |
| Modifier Groups | CRUD /modifier-groups + /options | ✅ |
| Tische/Zonen | CRUD /tables + /zones | ✅ |
| Kassensitzungen | open, close (+ Z-Bericht), current, /:id, /:id/z-report, movements | ✅ |
| Bestellungen | GET+POST /orders, GET /:id, items (add/remove), cancel, pay, pay/split | ✅ |
| Bons | GET /receipts (Liste), GET /receipts/:id, POST /:id/cancel | ✅ |
| Offline-Sync | GET+POST /sync/offline-queue | ✅ |
| Onboarding | POST /onboarding/register, POST /onboarding/create-checkout-session | ✅ |
| Stripe Webhook | POST /webhooks/stripe (alle Subscription-Events, Idempotenz) | ✅ |
| Berichte | GET /reports/daily, GET /reports/summary (Plan-Limit: 30/365/3650 Tage) | ✅ |
| DSFinV-K Export | GET /export/dsfinvk, /:exportId/status, /:exportId/file | ✅ |

### Noch nicht implementiert ❌
| Bereich | Endpoints | Phase |
|---------|-----------|-------|
| Bon-PDF | GET /receipts/:id/pdf | Phase 5 |

---

## Implementierungsstand SwiftUI Frontend

### Fertig implementiert ✅
| Screen / File | Inhalt | Stand |
|---------------|--------|-------|
| `DesignSystem.swift` | Alle Design-Tokens (Farben, Typo, Radii, Spacing) aus Design System v1.2 | ✅ |
| `AppError.swift` | App-weite Fehlertypen (LocalizedError, deutsche Meldungen) | ✅ |
| `Models.swift` | User, Tenant, UserRole, SubscriptionPlan, AuthResponse | ✅ |
| `AuthStore.swift` | ObservableObject: Login, PIN-Login, Logout, User-Cache (UserDefaults) | ✅ |
| `NetworkMonitor.swift` | NWPathMonitor Wrapper, isOnline @Published | ✅ |
| `OfflineBanner.swift` | Offline-Hinweisband "TSE-Signatur ausstehend" | ✅ |
| `LoginView.swift` | 2-Spalten Login: Brand-Panel + Formular, PIN-Liste, Dark-Mode-Toggle, PINEntrySheet | ✅ |
| `ContentView.swift` | Auth-Router: LoginView ↔ App | ✅ |
| `zettel_frontendApp.swift` | Root mit @StateObject Stores + EnvironmentObject Injection | ✅ |

### Noch nicht implementiert ❌ (SwiftUI — Reihenfolge laut Design System §7)
| Screen | Abhängigkeiten | Phase |
|--------|----------------|-------|
| `TableOverviewView` | OrderStore, SessionStore | Phase 1 |
| `OrderView` | OrderStore, ProductStore | Phase 1 |
| `ModifierSheet` | an OrderView gebunden (Modal) | Phase 1 |
| `PaymentView` | OrderStore, TSE-Flow | Phase 2 |
| `ReceiptView` | receipts-API, QR-Code | Phase 2 |
| `KassensitzungView` | SessionStore | Phase 1 (Pflicht vor Go-live) |
| `ZBerichtView` | sessions-API | Phase 2 (Pflicht vor Go-live) |
| `BerichteView` | reports-API | Phase 2 |
| `ProdukteView` | products-API | Phase 1 |
| `KategorienView` | products/categories-API | Phase 1 |
| `EinstellungenView` | tenants/users/devices-API | Phase 1 |

### SwiftUI — Offene Punkte
| Punkt | Details |
|-------|---------|
| Plus Jakarta Sans | Font-Dateien bundlen + Info.plist UIAppFonts + Font.jakarta() umstellen |
| APIClient | HTTP-Client mit JWT-Handling, Refresh-Logic, Base-URL konfigurierbar |
| OrderStore | @EnvironmentObject für Bestellungen, Tischstatus |
| SessionStore | @EnvironmentObject für Kassensitzung |
| SyncManager | Offline-Queue-Status, Retry-Logic |
| KeychainWrapper | JWT sicher im Keychain statt UserDefaults speichern |

### Offene Backend-Punkte (dokumentiert, noch nicht implementiert)
| Bereich | Details | Priorität |
|---------|---------|-----------|
| `versionMiddleware` | `X-App-Version`-Header prüfen, Deprecation-Warnings für alte iOS-Versionen | Vor Go-Live |
| Passwort-Reset | `POST /auth/forgot-password` + `/reset-password` via E-Mail-Token | Vor Go-Live |
| E-Mail-Service | Trial-Ablauf-Warnung, Subscription-Events, Passwort-Reset (Nodemailer/SES) | Vor Go-Live |
| Cron-Jobs | Trial-Ablauf (Tag 10+13), `past_due`-Sperrung, ELSTER-Frist-Prüfung bei TSE-Ausfall | Vor Go-Live |
| Admin-Panel | Tenant-Übersicht, manuelle Plan-Änderung, Audit-Einsicht | Phase 4 |

### Backend — Logging (implementiert ✅)
- **Pino** (`pino` + `pino-http`) — JSON-Logs in Production, Pretty-Print in Development
- `src/logger.ts` — zentraler Logger, via `LOG_LEVEL` env konfigurierbar (default: `info`)
- Jeder Request loggt: `method`, `url`, `status`, `responseTime`, `tenant` (aus JWT)
- 4xx → `warn`, 5xx → `error`, 2xx → `info` — `/health` wird nicht geloggt
- Globaler Error Handler nutzt `logger.error` statt `console.error`

### Auth — kritische Backend-Details
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
├── index.ts
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
│   ├── fiskaly.ts      -- TSE-Operationen + Offline-Fallback (enqueueOffline)
│   ├── priceHistory.ts -- product_price_history INSERT
│   ├── receipts.ts     -- Bon-Generierung + Pflichtfeld-Prüfung
│   └── sequences.ts    -- receipt_sequences FOR UPDATE
├── db/
│   ├── migrations/     -- V001__initial_schema, V002__order_items_soft_delete
│   ├── migrate.ts
│   └── index.ts
└── __tests__/
    ├── unit/
    │   └── vatCalculation.test.ts   -- MwSt-Berechnung + buildVatBreakdown
    ├── integration/    -- auth, cancellations, devices, export, mixed-payments,
    │                      modifierGroups, offline-queue, onboarding, orders,
    │                      payments, products, receipts, receipts-list, reports,
    │                      sessions, split-bill, stripe-webhooks, tables,
    │                      tenants, users
    │                   -- Tenant-Isolation-Tests sind in jeder dieser Dateien
    │                      als eigene it()-Blöcke enthalten
    ├── compliance/     -- receipt-fields (KassenSichV + GoBD Pflichtfelder)
    └── external/       -- fiskaly (Sandbox, nightly)
```

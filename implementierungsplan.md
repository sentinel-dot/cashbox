# Kassensystem SaaS — Vollständiger Implementierungsplan

## Kontext
iPad-basiertes Kassensystem für Gastronomie (Shishabar, Café, Späti) als SaaS-Produkt.
Stack: SwiftUI / Node.js+TypeScript / MariaDB / Fiskaly / Stripe.
Ziel: Vor Implementierungsstart alles vollständig durchdenken.

**Scope-Entscheidungen (bewusst):**
- Vorerst **kein Bondrucker** — digitaler Bon (In-App-Anzeige + PDF per E-Mail optional)
- Vorerst **kein Multi-iPad** — Single-Device-Betrieb für Pilot; WebSocket-Events als Vorbereitung
- Bondrucker und Multi-iPad kommen später als separate Meilensteine
- **Kein Trinkgeld** in Phase 1-2 — Feature erst nach Steuerberater-Klärung (Phase 3+, nur Barzahlung)
- **Außer-Haus-Toggle deaktiviert** für Phase 1-3 — Datenmodell vorbereitet, aber UI/Logic aus; für Shishabar-Pilot irrelevant (Shisha = immer 19%, kein echter Takeaway-Betrieb)

---

## 1. Datenbankstruktur (MariaDB, GoBD-konform)

**Grundregel:** Keine UPDATE/DELETE auf Finanzdaten. Storno = Gegenbuchung. 10 Jahre Aufbewahrung.

### Tenants & Users
```sql
tenants (
  id, name,
  address TEXT,                -- Vollständige Adresse (Pflichtfeld auf Bon)
  vat_id VARCHAR,              -- USt-IdNr. (Pflichtfeld auf Bon)
  tax_number VARCHAR,          -- Steuernummer (Pflichtfeld auf Bon)
  fiskaly_tss_id VARCHAR,      -- pro Kunde eine eigene TSS
  stripe_customer_id, stripe_subscription_id,
  subscription_current_period_end DATETIME,  -- Ende des Stripe-Abrechnungszeitraums (invoice.payment_succeeded)
  plan ENUM('starter','pro','business'),
  subscription_status ENUM('trial','active','past_due','cancelled'),  -- trial = 14 Tage ab created_at
  data_retention_until DATE,   -- GoBD: 10 Jahre nach letzter Transaktion/Kündigung
  created_at
)

users (
  id, tenant_id, name, email, password_hash,
  role ENUM('owner','manager','staff'),
  pin_hash VARCHAR,            -- 4-stellige PIN für schnellen iPad-Wechsel
  is_active BOOLEAN,           -- soft delete
  created_at
)

devices (
  id, tenant_id, name,
  device_token VARCHAR,        -- rotierbar bei Verlust
  device_token_hash VARCHAR,   -- nur Hash in DB, nicht Klartext
  tse_client_id VARCHAR,       -- Fiskaly Client-ID pro Gerät (jedes Gerät = eigener Client)
  is_revoked BOOLEAN DEFAULT FALSE,
  last_seen_at, created_at
)
```

### Produkte
```sql
product_categories (
  id, tenant_id, name, color, sort_order, is_active
)

products (
  id, tenant_id, category_id, name,
  price_cents INT,             -- Preise immer in Cent — NIEMALS updaten, nur product_price_history
  vat_rate_inhouse ENUM('7','19'),    -- MwSt Inhaus — NIEMALS updaten, nur product_price_history
  vat_rate_takeaway ENUM('7','19'),   -- MwSt Außer-Haus (Phase 4+, vorerst = vat_rate_inhouse)
  is_active BOOLEAN,           -- soft delete — darf geupdated werden (kein Finanzdatum)
  created_at, updated_at       -- updated_at für name/is_active/category_id erlaubt
  -- NUR price_cents + vat_rate_* sind immutable → Änderungen via product_price_history
)

product_price_history (
  id, product_id, tenant_id,
  price_cents INT,
  vat_rate_inhouse ENUM('7','19'),
  vat_rate_takeaway ENUM('7','19'),
  changed_by_user_id,
  valid_from DATETIME NOT NULL,
  created_at
  -- DB-User: NUR INSERT-Rechte
  -- Ermöglicht: "Was hat Produkt X am Stichtag Y gekostet?" — auch ohne Transaktion
)

product_modifier_groups (
  id, tenant_id,
  product_id INT NULL,         -- NULL wenn category_id gesetzt
  category_id INT NULL,        -- Gruppe gilt für alle Produkte dieser Kategorie
  name VARCHAR,                -- z.B. "Tabaksorte", "Kopfgröße", "Extras"
  is_required BOOLEAN,         -- TRUE = Kellner muss Auswahl treffen vor Hinzufügen
  min_selections INT DEFAULT 0,-- 0 = optional
  max_selections INT NULL,     -- NULL = unbegrenzt, 1 = Einzelauswahl
  is_active BOOLEAN DEFAULT TRUE, -- soft delete der ganzen Gruppe
  sort_order INT DEFAULT 0
  -- Entweder product_id ODER category_id gesetzt, nicht beides
)

product_modifier_options (
  id, modifier_group_id, tenant_id,
  name VARCHAR,                -- z.B. "Al Fakher Mint", "Groß", "Mit Eis"
  price_delta_cents INT DEFAULT 0,  -- 0 = inklusive, 200 = +2,00€
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INT DEFAULT 0
)
```

> **Modifier-Logik:** `subtotal_cents` in `order_items` = `(product_price_cents + SUM(modifier price_deltas)) × quantity - discount_cents`

> **Außer-Haus / Takeaway (MVP-Entscheidung):** Feature im Code vorbereitet (Felder vorhanden),
> aber UI-Toggle und Steuer-Logik deaktiviert für Phase 1-3. Für Shishabar-Pilot irrelevant:
> Shisha-Tabak ist immer 19%, echter Takeaway-Betrieb existiert nicht. Aktivierung in Phase 4
> — Tenant konfiguriert Sätze nach Absprache mit eigenem Steuerberater.

### Tische & Zonen
```sql
zones (id, tenant_id, name, sort_order)
tables (id, tenant_id, zone_id, name, is_active)
-- table_id in orders ist NULLABLE → Schnellverkauf ohne Tisch (Theke / Späti)
```

### Bon-Nummern-Sequenz (GoBD-konform, atomar)
```sql
receipt_sequences (
  tenant_id INT PRIMARY KEY,
  last_number INT NOT NULL DEFAULT 0
  -- Zugriff NUR via: SELECT ... FOR UPDATE → Increment → Commit
  -- Rollback nach Nummernvergabe: Nummer mit Status 'voided' in receipts speichern
  -- AUTO_INCREMENT auf receipts.receipt_number ist VERBOTEN (Lücken bei Rollback)
)
```

> **Kritisch:** Bon-Nummern-Lücken sind ein GoBD-Problem. Wenn eine Transaktion nach
> Nummernvergabe fehlschlägt, muss die Nummer mit `status='voided'` und `void_reason` in
> `receipts` dokumentiert werden — niemals einfach skippen.

### Kassensitzungen / Schichten (GoBD: Z-Bericht-Grundlage)
```sql
cash_register_sessions (
  id, tenant_id, device_id,
  opened_by_user_id, opened_at,
  closed_by_user_id, closed_at,
  opening_cash_cents INT,      -- Anfangsbestand (manuell gezählt)
  closing_cash_cents INT,      -- Endbestand (manuell gezählt)
  expected_cash_cents INT,     -- berechnet: Anfang + Einnahmen + Einlagen - Entnahmen
  difference_cents INT,        -- Abweichung (Soll - Ist)
  status ENUM('open','closed'),
  created_at
  -- z_report_json gehört NICHT hierher — eigene Tabelle (siehe z_reports)
)
-- WICHTIG: GoBD verlangt täglichen Abschluss — Cron-Job warnt bei >24h offener Session

z_reports (
  id, session_id, tenant_id,
  report_json JSON NOT NULL,   -- unveränderlicher Snapshot des Z-Berichts
  created_at
  -- DB-User: NUR INSERT-Rechte, kein UPDATE/DELETE — GoBD-Unveränderlichkeit
)
```

### Einlagen & Entnahmen (Kassenbuch)
```sql
cash_movements (
  id, session_id, tenant_id,
  type ENUM('deposit','withdrawal'),
  amount_cents INT,
  reason VARCHAR NOT NULL,     -- z.B. "Wechselgeld einlegen", "Betriebsausgabe"
  created_by_user_id,
  created_at
)
```

### Bestellungen (GoBD: nie löschen)
```sql
orders (
  id, tenant_id,
  table_id INT NULL,           -- NULL = Schnellverkauf/Theke ohne Tisch
  session_id INT,              -- Kassensitzung (für Z-Bericht-Zuordnung)
  is_takeaway BOOLEAN DEFAULT FALSE,  -- Außer-Haus-Bestellung
  opened_by_user_id,
  status ENUM('open','paid','cancelled'),
  created_at,
  closed_at                    -- KassenSichV: Transaktionsende dokumentieren
)

order_items (
  id, order_id, product_id,
  product_name VARCHAR,        -- SNAPSHOT zum Bestellzeitpunkt
  product_price_cents INT,     -- SNAPSHOT (Preisänderungen dürfen Bons nicht ändern)
  vat_rate ENUM('7','19'),     -- SNAPSHOT (inkl. Außer-Haus-Korrektur)
  quantity INT,
  subtotal_cents INT,          -- nach Rabatt
  discount_cents INT DEFAULT 0,
  discount_reason VARCHAR,     -- Pflichtfeld wenn discount_cents > 0
  added_by_user_id,
  created_at
  -- KEIN DELETE: Stornierungen über cancellations-Tabelle
)

order_item_modifiers (
  id, order_item_id,
  modifier_option_id,
  option_name VARCHAR,         -- SNAPSHOT (Name zum Bestellzeitpunkt)
  price_delta_cents INT,       -- SNAPSHOT (Aufpreis zum Bestellzeitpunkt)
  created_at
)
```

### Zahlungen & Bons (TSE)
```sql
payments (
  id, order_id, receipt_id,   -- Relation zu Receipt (für gemischte Zahlung)
  method ENUM('cash','card'),
  amount_cents INT,
  tip_cents INT,               -- Trinkgeld separat (kein MwSt)
  paid_at, paid_by_user_id
  -- Ein Order kann MEHRERE payments haben (gemischte Zahlung: Bar + Karte)
)

receipts (
  id, tenant_id, order_id, session_id,
  receipt_number INT,          -- fortlaufend pro Tenant, NIEMALS zurücksetzen
  status ENUM('active','voided'),     -- voided = Nummernlücke dokumentiert
  void_reason VARCHAR,         -- wenn status='voided'
  is_split_receipt BOOLEAN DEFAULT FALSE,  -- Teilrechnung bei Split Bill
  split_group_id INT,          -- gemeinsame ID aller Split-Bons einer Order
  -- Gerät (§ 6 Abs. 1 Nr. 6 KassenSichV: Seriennummer des Aufzeichnungssystems):
  device_id INT NOT NULL,      -- welches iPad hat den Bon erstellt
  device_name VARCHAR NOT NULL,-- Snapshot des Gerätenamens (z.B. "iPad Theke")
  -- TSE-Daten (Pflichtfelder § 6 KassenSichV):
  tse_transaction_id VARCHAR,
  tse_serial_number VARCHAR,
  tse_signature TEXT,
  tse_counter INT,
  tse_transaction_start DATETIME,
  tse_transaction_end DATETIME,
  tse_pending BOOLEAN DEFAULT FALSE,
  -- MwSt-Aufschlüsselung:
  vat_7_net_cents INT,
  vat_7_tax_cents INT,
  vat_19_net_cents INT,
  vat_19_tax_cents INT,
  total_gross_cents INT,
  tip_cents INT DEFAULT 0,     -- Trinkgeld (Phase 3+, immer 0 bis dahin)
  is_takeaway BOOLEAN DEFAULT FALSE,  -- Außer-Haus-Vermerk (Phase 4+)
  raw_receipt_json JSON,       -- vollständiger Bon als JSON (Archiv, nur einmal geschrieben)
  created_at
  -- WICHTIG: raw_receipt_json wird NUR beim finalen status='active' befüllt.
  -- Danach kein UPDATE auf dieses Feld (Application-Level-Enforcement)
)
```

### Split Bill
```sql
payment_splits (
  id, order_id,
  receipt_id INT,              -- eigener Bon pro Split
  items_json JSON,             -- welche order_items in diesem Split
  total_cents INT,
  created_by_user_id,
  created_at
  -- Jeder Split = eigene TSE-Transaktion + eigener Bon
)
```

### Storno (GoBD: Gegenbuchung, nie löschen)
```sql
cancellations (
  id,
  original_receipt_id,         -- Referenz auf Original-Bon
  original_receipt_number INT, -- denormalisiert für Bon-Ausdruck (Lesbarkeit)
  cancellation_receipt_id,     -- neuer Storno-Bon (negative TSE-Transaktion)
  cancelled_by_user_id,
  reason TEXT NOT NULL,
  created_at
)
```

### Offline-Queue (TSE-Signatur nachholen)
```sql
offline_queue (
  id, tenant_id, device_id,
  order_id,
  payload_json JSON,
  idempotency_key VARCHAR UNIQUE,  -- verhindert doppelte TSE-Transaktion bei Timeout
  status ENUM('pending','processing','completed','failed'),
  retry_count INT DEFAULT 0,
  error_message TEXT,
  created_at, synced_at
)
```

### Audit-Log (GoBD: unveränderlich)
```sql
audit_log (
  id, tenant_id, user_id,
  action VARCHAR,              -- z.B. 'order.item_removed', 'receipt.created'
  entity_type VARCHAR,
  entity_id INT,
  diff_json JSON,              -- old/new Werte
  ip_address VARCHAR,
  device_id INT,               -- von welchem Gerät
  created_at
  -- DB-Benutzer: NUR INSERT-Rechte, kein UPDATE/DELETE (per DB-Permission)
)
```

### Stripe Events
```sql
subscription_events (
  id, tenant_id, stripe_event_id VARCHAR UNIQUE,
  event_type VARCHAR,
  payload_json JSON,
  processed BOOLEAN DEFAULT FALSE,
  created_at
)
```

### TSE-Ausfall Monitoring
```sql
tse_outages (
  id, tenant_id, device_id,
  started_at DATETIME,
  ended_at DATETIME,
  notified_at DATETIME,        -- wann Tenant-Owner benachrichtigt wurde
  reported_to_finanzamt BOOLEAN DEFAULT FALSE,  -- Pflicht nach 48h Ausfall
  created_at
)
```

---

## 2. TSE-Anbieter: Entscheidung Fiskaly

**Fiskaly ist die richtige Wahl.** Begründung und Alternativen:

| Anbieter | Typ | Für dieses Projekt |
|----------|-----|--------------------|
| **Fiskaly** | Cloud-TSE (API) | ✅ Beste Wahl: REST API, Multi-Tenant, DSFinV-K-Export eingebaut, Sandbox, aktive iOS-Community |
| Deutsche Fiskal | Cloud-TSE (API) | Ähnlich zu Fiskaly, weniger Dokumentation/Community |
| Swissbit | Hardware-TSE (USB/SD) | ❌ Nicht geeignet für Cloud-SaaS; Hardware muss an jedem Gerät hängen |
| Epson TSE | Hardware-TSE | ❌ Gleiche Hardware-Problematik |
| A-Trust | Cloud-TSE (AT/EU) | Weniger verbreitet in DE, Compliance-Prüfung nötig |

**Fiskaly-Vorteile konkret:**
- Eine API für alle Tenants (jeder Tenant = eigene TSS, jedes iPad = eigener Client)
- DSFinV-K-Export über dieselbe API (kein eigenes Build nötig)
- Gut dokumentierte Sandbox für Entwicklung
- Wird von vielen deutschen POS-Startups genutzt (starke Community)
- Preismodell: Pro TSS (= pro Tenant) — passt zu SaaS

**Achtung:** Fiskaly ist ein österreichisches Unternehmen mit DE-Zertifizierung. TSE-Zertifikat
durch BSI geprüft. Stand 2025 nach wie vor vollständig KassenSichV-konform.

---

## 3. Backend API (Node.js / TypeScript / Express)

### Validierung
**Zod** für alle Eingaben — kein Request ohne Schema-Validierung. Gilt für:
- Alle POST/PATCH-Endpunkte
- Stripe Webhook Payload
- Offline-Queue Payload

### Auth
```
✅ POST   /auth/login              → {token, refreshToken, user}
✅ POST   /auth/logout             → stateless, gibt nur {ok:true} (kein Test nötig)
✅ POST   /auth/refresh
✅ POST   /auth/pin                → PIN-basierter Benutzer-Switch auf Gerät
```

### Onboarding (öffentlich, Rate-Limited — 3/min/IP)
```
✅ POST   /onboarding/register               → Tenant + Owner-User + erstes Gerät + receipt_sequences
                                               atomar in einer TX; gibt vollständiges JWT zurück
                                               Body: business_name, email, password, address,
                                               tax_number, device_name, device_token
✅ POST   /onboarding/create-checkout-session → Stripe Customer anlegen (falls neu), Checkout-URL
                                               Body: plan ('starter'|'pro'|'business'),
                                               success_url, cancel_url
```

### Tenant
```
✅ GET    /tenants/me
✅ PATCH  /tenants/me              → inkl. Adresse, Steuernummer, USt-ID (Bon-Pflichtfelder!)
```

### Users
```
✅ GET    /users
✅ POST   /users
✅ PATCH  /users/:id
✅ DELETE /users/:id               → soft delete (is_active=false)
```

### Geräte (Device-Management)
```
✅ POST   /devices/register        → Device-Token generieren + Fiskaly Client anlegen
✅ POST   /devices/:id/revoke      → Token ungültig machen (bei Verlust)
✅ GET    /devices                 → alle Geräte des Tenants
```

### Produkte
```
✅ GET    /products                → inkl. Kategorien + Modifier-Gruppen + Optionen
✅ POST   /products
✅ PATCH  /products/:id
✅ DELETE /products/:id            → soft delete
✅ POST   /products/:id/price      → Preisänderung via product_price_history (GoBD)

✅ GET    /products/categories
✅ POST   /products/categories
✅ PATCH  /products/categories/:id
✅ DELETE /products/categories/:id

✅ GET    /modifier-groups         → alle Gruppen des Tenants (inkl. Optionen)
✅ POST   /modifier-groups         → {product_id|category_id, name, is_required, min, max}
✅ PATCH  /modifier-groups/:id
✅ DELETE /modifier-groups/:id     → soft delete (is_active=false auf alle Optionen)

✅ POST   /modifier-groups/:id/options     → {name, price_delta_cents}
✅ PATCH  /modifier-groups/:id/options/:optId
✅ DELETE /modifier-groups/:id/options/:optId → soft delete
```

### Tische
```
✅ GET    /tables                  → inkl. Zone + aktueller Order-Status
✅ POST   /tables
✅ PATCH  /tables/:id
✅ DELETE /tables/:id              → soft delete
✅ GET    /zones
✅ POST   /zones
✅ PATCH  /zones/:id
```

### Kassensitzungen
```
✅ POST   /sessions/open           → {opening_cash_cents}
✅ POST   /sessions/close          → {closing_cash_cents} → Z-Bericht generieren + in z_reports speichern
✅ GET    /sessions/current        → aktuelle offene Sitzung
✅ GET    /sessions/:id            → Sitzungsdetails
✅ GET    /sessions/:id/z-report   → Z-Bericht aus z_reports (unveränderlich, read-only)
✅ POST   /sessions/:id/movements  → {type, amount_cents, reason}  Einlage/Entnahme
-- Cron-Job: täglich prüfen ob Session > 24h offen → Push-Notification + E-Mail an Owner
```

### Bestellungen (Kern-Flow)
```
✅ GET    /orders                  → alle offenen Bestellungen (aktueller Session)
✅ POST   /orders                  → {table_id?, is_takeaway}
✅ GET    /orders/:id
✅ POST   /orders/:id/items        → {product_id, quantity, modifier_option_ids?: [], discount_cents?, discount_reason?}
                                   Voraussetzung: offene Kassensitzung (sonst 409)
                                   Backend validiert:
                                   - Alle required Modifier-Gruppen abgedeckt? (sonst 422)
                                   - modifier_option_ids gehören zum Produkt dieses Tenants? (sonst 403)
✅ DELETE /orders/:id/items/:itemId → INSERT INTO order_item_removals (GoBD: kein DELETE)
✅ POST   /orders/:id/pay          → Einfache Zahlung + gemischte Zahlung
                                   {method, amount_cents} oder {payments: [{method, amount_cents}]}
                                   -- tip_cents Phase 3+
                                   Voraussetzung: offene Kassensitzung (sonst 409)
                                   1. receipt_sequences FOR UPDATE → Nummer holen
                                   2. Fiskaly TSE-Transaktion (mit idempotency_key)
                                   3. Receipt erstellen
                                   4. Payment(s) erstellen
   HINWEIS: paymentsController ist direkt in orders-Route eingebunden (KEIN /payments-Endpoint)
✅ POST   /orders/:id/pay/split    → Split Bill
                                   {splits: [{item_ids: []}]}
                                   → pro Split: eigene TSE-Transaktion + eigener Bon
✅ POST   /orders/:id/cancel       → {reason}
                                   Storno: negative TSE-Transaktion + Storno-Bon
                                   Storno-Bon enthält Original-Bon-Nummer lesbar
```

### Bons
```
✅ GET    /receipts/:id            → inkl. raw_receipt_json, alle Pflichtfelder
✅ POST   /receipts/:id/cancel     → Storno-Bon (via cancellationsController)
✅ GET    /receipts                → Listenansicht (?from=&to=&session_id=&limit=&offset=, Plan-Limit)
❌ GET    /receipts/:id/pdf        → PDF-Bon (Phase 5)
```

### Berichte
```
✅ GET    /reports/daily           → ?date=   Tagesübersicht (MwSt, Zahlungsarten, Sessions, Stornos)
✅ GET    /reports/summary         → ?from=&to=  Zeitraum + pro-Tag-Aufschlüsselung (Plan-Limit)
-- Z-Bericht läuft über Sessions: GET /sessions/:id/z-report ✅
```

### DSFinV-K Export
```
✅ GET    /export/dsfinvk                  → ?from=&to=  TAR mit DSFinV-K-Daten (Fiskaly API)
                                             Trigger → Poll (8s) → Datei proxyen oder 202 + export_id
✅ GET    /export/dsfinvk/:exportId/status → Polling-Endpoint für laufende Exports
✅ GET    /export/dsfinvk/:exportId/file   → TAR-Download wenn state=COMPLETED
```

### Offline-Sync
```
✅ GET    /sync/offline-queue      → Status-Übersicht (pending/processing/completed/failed)
✅ POST   /sync/offline-queue      → Batch-Signierung ausstehender Offline-Bons
                                   Idempotenz: bereits abgeschlossene TX nicht neu starten
```

### Stripe Webhook (Signatur-Validierung Pflicht!)
```
✅ POST   /webhooks/stripe
-- stripe.webhooks.constructEvent() mit rawBody (Buffer aus express.raw())
-- Idempotenz via stripe_events-Tabelle (PRIMARY KEY auf event.id)
-- Events: customer.subscription.created/updated/deleted,
--         invoice.payment_succeeded/failed, checkout.session.completed
-- tenant_id immer via stripe_customer_id auflösen — nie aus Body
-- Unbekannte Events: immer 200 (kein Retry)
```

### Middleware-Stack
- `rateLimitMiddleware` — Login: 5/min, Onboarding: 3/min, allgemein: 100/min
- `authMiddleware` — JWT validieren + Ablauf prüfen
- `deviceMiddleware` — Device-Token validieren + is_revoked prüfen
- `tenantMiddleware` — tenant_id aus JWT, alle Queries auf tenant_id scopen
- `subscriptionMiddleware` — trial: OK für 14 Tage ab created_at (X-Trial-Expires Header);
                              active: OK; past_due: OK + X-Subscription-Warning (3 Tage Grace);
                              cancelled: 402
- `sessionMiddleware` — 409 wenn keine offene Kassensitzung (gilt für Orders + Payments)
- `planMiddleware` — Geräteanzahl / Features gegen Plan prüfen
- `validationMiddleware(schema)` — Zod-Schema pro Route

---

## 4. Fiskaly TSE — Transaktionsflow

### Standard-Zahlung
```
1. POST /api/v2/tss/{tss_id}/tx
   body: { type: "RECEIPT", state: "ACTIVE", client_id: device.tse_client_id }
   → tx_id, revision=0

2. PUT /api/v2/tss/{tss_id}/tx/{tx_id}?last_revision=0
   body: {
     state: "ACTIVE",
     schema: {
       standard_v1: {
         receipt: {
           receipt_type: "RECEIPT",
           amounts_per_vat_rates: [
             { vat_rate: "NORMAL", amount: "XX.XX" },   // 19%
             { vat_rate: "REDUCED_1", amount: "XX.XX" } // 7%
           ],
           amounts_per_payment_types: [
             { payment_type: "CASH", amount: "XX.XX" },
             { payment_type: "NON_CASH", amount: "XX.XX" }  // bei gemischter Zahlung beide
           ]
         }
       }
     }
   }
   → revision=1

3. PUT /api/v2/tss/{tss_id}/tx/{tx_id}/finish?last_revision=1
   → signature.value, tss.serial_number, signature.counter,
     log_time.unix_timestamp_utc (start+end)
```

### Idempotenz bei Timeout (kritisch!)
```
Problem: PUT finish → Timeout → erneuter Aufruf → 409 Conflict (bereits abgeschlossen)

Lösung:
1. Vor neuem finish-Request: GET /tx/{tx_id} prüfen
2. Wenn status="FINISHED": Antwort aus vorherigem Call rekonstruieren
3. idempotency_key in offline_queue verhindert doppelten TX-Start
4. Jede TSE-Operation mit try/catch + Recovery-Pfad implementieren
```

### Offline-Strategie
1. iPad erkennt Offline-Status via `NetworkMonitor`
2. Bestellung läuft normal, Zahlung wird lokal gespeichert
3. Bon wird OHNE TSE-Daten angezeigt — mit Vermerk **"TSE-Signatur ausstehend"**
4. `offline_queue`-Eintrag mit `idempotency_key` erstellt
5. `SyncManager` verarbeitet Queue bei Reconnect (FIFO, exponential backoff)
6. Nach Signierung: Receipt mit TSE-Daten befüllt, Bon-Ansicht aktualisiert
7. In `audit_log`: jede verzögerte Signierung mit Timestamp dokumentiert

### TSE-Ausfall > 48h: Meldepflicht
- Nach 48h: automatische E-Mail an Tenant-Owner + Eintrag in `tse_outages`
- Tenant-Owner muss Finanzamt informieren (Prozess im Onboarding erklären)
- System bleibt im Offline-Modus weiter nutzbar (mit Vermerk auf Bon)

---

## 5. Bon-Pflichtfelder (vollständige Liste)

Alle müssen auf dem digitalen Bon (PDF/Anzeige) sichtbar sein:

| Feld | Quelle | Gesetzliche Grundlage |
|------|--------|----------------------|
| Vollständiger Unternehmensname | `tenants.name` | § 14 UStG |
| Vollständige Adresse | `tenants.address` | § 14 UStG |
| Steuernummer ODER USt-IdNr. | `tenants.tax_number` / `tenants.vat_id` | § 14 UStG |
| Bon-Nummer (fortlaufend) | `receipts.receipt_number` | KassenSichV |
| Datum und Uhrzeit | `receipts.created_at` | KassenSichV |
| TX-Beginn Timestamp | `receipts.tse_transaction_start` | KassenSichV |
| TX-Ende Timestamp | `receipts.tse_transaction_end` | KassenSichV |
| **Kassensystem-Bezeichnung + ID** | `receipts.device_name` + `receipts.device_id` | **§ 6 Abs. 1 Nr. 6 KassenSichV** |
| Jede Position: Name, Menge, Einzelpreis, Gesamt | `order_items` Snapshot | § 14 UStG |
| MwSt-Aufschlüsselung (7% und 19% getrennt) | `receipts.vat_*` | § 14 UStG |
| Zahlungsart(en) | `payments.method` | KassenSichV |
| TSE-Seriennummer | `receipts.tse_serial_number` | KassenSichV |
| TSE-Signatur | `receipts.tse_signature` | KassenSichV |
| TX-Counter | `receipts.tse_counter` | KassenSichV |
| QR-Code mit TSE-Daten | generiert aus TSE-Feldern | BSI TR-03153 (erwartet) |
| Bei Außer-Haus: Vermerk + korrekter MwSt-Satz | `orders.is_takeaway` | UStG (Phase 4+) |
| Bei Storno: Referenz auf Original-Bon-Nummer | `cancellations.original_receipt_number` | GoBD |
| Bei Rabatt: Betrag + Grund | `order_items.discount_*` | GoBD |

---

## 6. Business Logic — Kern-Features

### Gemischte Zahlung (häufig in Gastronomie)
```
Szenario: 30€ Rechnung → 10€ Bar + 20€ Karte

Flow:
1. POST /orders/:id/pay-mixed mit payments-Array
2. Ein Receipt für die Order
3. Mehrere payment-Einträge (einer pro Zahlungsart)
4. TSE: amounts_per_payment_types enthält alle Zahlungsarten
5. Bon zeigt: "Bar: 10,00€ | Karte: 20,00€ | Gesamt: 30,00€"
```

### Split Bill (Standard in Restaurantbetrieb)
```
Szenario: 4 Personen zahlen getrennt

Flow:
1. POST /orders/:id/split mit splits-Array (Positionen zuweisen)
2. Pro Split: eigene TSE-Transaktion + eigene Bon-Nummer
3. payment_splits-Tabelle verknüpft Items → Split-Receipt
4. Alle Split-Bons referenzieren dieselbe Order
5. Gemischte Zahlung pro Split ebenfalls möglich
```

### Schnellverkauf / Theke (ohne Tisch)
```
Szenario: Späti-Betrieb, Theke, Foodtruck

Flow:
1. POST /orders mit table_id=null
2. Keine Tischauswahl nötig
3. Direkter Übergang zu Produktauswahl → Zahlung
4. Bon ohne Tischbezeichnung
5. "Schnellkasse"-Modus in App: vereinfachter UI-Flow
```

### Außer-Haus / Takeaway
```
Szenario: Café — Kaffee to go (19%) statt Inhaus (7%)

Flow:
1. Order wird mit is_takeaway=true erstellt (oder per Toggle wechselbar)
2. vat_rate in order_items wird aus product.vat_rate_takeaway befüllt
3. Bon trägt Vermerk "Außer Haus"
4. Steuerberater muss pro Betrieb klären: welche Produkte sind betroffen
```

### Trinkgeld (Phase 3+, erst nach Steuerberater)

**MVP-Entscheidung: Feature komplett deaktiviert in Phase 1-2.**

Wenn Trinkgeld später eingebaut wird (Phase 3, nur Barzahlung):
- Trinkgeld geht direkt an den Mitarbeiter, läuft nicht als Einnahme durch die Kasse
- Bon: zeigt Trinkgeld separat als Info-Feld, kein MwSt
- TSE: Trinkgeld wird zur Zahlungsart addiert (kein eigener payment_type):
  ```
  Rechnung 30€ + 5€ Trinkgeld bar:
  → TSE amounts_per_payment_types: CASH = 35,00 (Gesamt inkl. Trinkgeld)
  → DB: payments.amount_cents=3000, payments.tip_cents=500
  → Bon: Subtotal 30,00€ | Trinkgeld 5,00€ | Gesamt 35,00€
  ```
- Kartenzahlung + Trinkgeld: **erst nach Steuerberater** — wird immer zu Betriebsumsatz

> **⚠ Haftungshinweis:** Die steuerliche Behandlung von Trinkgeld (Betriebseinnahme vs.
> steuerfreies Arbeitnehmertrinkgeld) ist betriebsindividuell und lohnsteuerrelevant.
> Vor Aktivierung dieser Funktion: schriftliche Klärung mit Steuerberater.

### Produktvarianten / Modifikatoren

```
Konfiguration (Admin):
  Shisha → Modifier-Gruppe "Tabaksorte" (required, max 1)
         → Modifier-Gruppe "Kopfgröße"  (required, max 1)
         → Modifier-Gruppe "Extras"     (optional, max unbegrenzt)

Bestellflow:
  Kellner tippt "Shisha 25€"
  → ModifierSheet öffnet
  → Pflichtauswahl: Tabaksorte + Kopfgröße (Hinzufügen-Button gesperrt bis beide gewählt)
  → Optionale Extras: Checkboxen
  → Aufpreis wird live summiert: "Hinzufügen 33,00€"
  → POST /orders/:id/items mit modifier_option_ids: [3, 7, 12]

Backend:
  1. Modifier-Optionen laden, Snapshots schreiben (order_item_modifiers)
  2. subtotal_cents = (25,00 + 3,00 + 5,00 + 0,00) × 1 = 33,00€
  3. Validierung: alle required Gruppen abgedeckt? Sonst 422

Bon:
  Shisha                       25,00€
    Tabak: Premium XY          +3,00€
    Kopf: Groß                 +5,00€
    Extra: Mit Eis              0,00€
  Gesamt Position              33,00€
```

### Storno (GoBD)
```
1. Original-Bon bleibt unverändert
2. Neue negative TSE-Transaktion (selber Flow, negative Beträge)
3. Storno-Bon: Bon-Nummer + Referenz auf Original-Bon-Nummer (lesbar, nicht nur DB)
4. Eintrag in cancellations mit reason + cancelled_by
5. Order-Status → 'cancelled'
```
- Partial-Storno (einzelne Positionen): Storno-Bon mit nur den stornierten Items
- `reason TEXT NOT NULL` — Pflichtfeld, kein Storno ohne Begründung

---

## 7. SwiftUI App-Struktur

### Screens
```
LoginView
├── TableOverviewView (Haupt-Screen)
│   ├── Tabs: Zonen (Innen / Außen / Bar)
│   ├── Tischkarten: Status (frei/besetzt/Rechnung)
│   ├── "+ Schnellkasse" Button (Order ohne Tisch)
│   └── → OrderView (Tisch antippen oder Schnellkasse)
│       ├── [Phase 4+] is_takeaway Toggle (Außer-Haus?) — in Phase 1-3 ausgeblendet
│       ├── Produktgitter (nach Kategorien)
│       │   └── Produkt antippen → ModifierSheet (wenn required groups vorhanden)
│       │       ├── Pflichtauswahl (z.B. Tabaksorte, Kopfgröße) — blockiert "Hinzufügen"
│       │       ├── Optionale Extras (Checkboxen)
│       │       └── Aufpreise live aktualisiert, "Hinzufügen X,XX€" Button
│       ├── Warenkorb (aktuelle Bestellung, Modifier pro Position angezeigt)
│       └── → PaymentView
│           ├── MwSt-Aufschlüsselung
│           ├── [Phase 3+] Trinkgeld-Eingabe — in Phase 1-2 ausgeblendet
│           ├── Zahlungsart (Bar / EC / Gemischt)
│           ├── Split Bill Option
│           └── → ReceiptView (digitaler Bon — kein Drucker!)
│               ├── Bon-Anzeige mit allen Pflichtfeldern
│               ├── QR-Code (TSE-Daten)
│               └── "PDF senden" Option
├── SessionView (Kassensitzung öffnen/schließen)
├── ProductManagementView (Admin)
├── ReportsView (Z-Bericht, Tagesübersicht)
└── SettingsView
    ├── Benutzerverwaltung
    ├── Geräteverwaltung
    └── Abo-Info
```

### Navigation
- `NavigationSplitView` (iPad-optimiert): Sidebar Tischliste, Detail Bestellung
- `TabView` für Hauptbereiche

### State Management
```swift
AuthStore           // @EnvironmentObject: user, token, tenant
OrderStore          // @StateObject: alle offenen Orders, Tischstatus
SessionStore        // @StateObject: aktuelle Kassensitzung
SyncManager         // @EnvironmentObject: Offline-Queue, Sync-Status
NetworkMonitor      // @EnvironmentObject: isOnline
```

> Kein PrinterManager in Phase 1. StarIO SDK kommt als separater Meilenstein.

### Core Data Entities (Offline-Caching)
```
CDProduct (id, name, price_cents, vat_rate_inhouse, vat_rate_takeaway, category, synced_at)
CDModifierGroup (id, product_id, category_id, name, is_required, min_selections, max_selections)
CDModifierOption (id, group_id, name, price_delta_cents, is_active, sort_order)
CDOrder (id, table_id, status, is_takeaway, created_at, sync_status)
CDOrderItem (id, order_id, product_id, quantity, price_cents, vat_rate, subtotal_cents)
CDOrderItemModifier (id, order_item_id, option_id, option_name, price_delta_cents)
CDOfflineQueue (id, order_id, idempotency_key, payload, status, created_at)
```

---

## 8. Security

### Authentifizierung & Geräte
- JWT + Refresh Token (kurze Laufzeit: 15min / 7 Tage)
- Device Token: gehashter Token in DB, Klartext nur bei Ausstellung
- Device-Revocation: `POST /devices/:id/revoke` → sofort wirksam (Middleware prüft `is_revoked`)
- PIN-basierter Benutzerwechsel auf Gerät (nicht für sensitive Operationen)

### Rate Limiting (Express Rate Limit)
```
Login:          5 Versuche / Minute / IP
Onboarding:     3 Versuche / Minute / IP
API allgemein:  100 Requests / Minute / Tenant
Offline-Sync:   10 Requests / Minute / Gerät
```

### Input-Validierung
- **Zod** für alle Request-Schemas
- Alle Geldbeträge: Integer (Cent), niemals Float
- Alle Enum-Felder: Whitelist-Validierung
- SQL Injection: ausschließlich Prepared Statements (kein String-Concatenation)

### Stripe Webhook
```typescript
// PFLICHT: Raw Body Middleware vor JSON-Parsing
app.post('/webhooks/stripe', express.raw({type: 'application/json'}), handler)

// PFLICHT: Signatur validieren
stripe.webhooks.constructEvent(rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET)

// PFLICHT: Idempotenz via stripe_event_id UNIQUE in subscription_events
```

### Secrets Management
- Alle Secrets in Umgebungsvariablen (nie in Code oder Logs)
- Fiskaly API Key, Stripe Secret, JWT Secret: `.env` lokal, Hetzner-Server-Env in Produktion
- Audit-Log-DB-User: NUR INSERT-Rechte (kein UPDATE/DELETE per GRANT)
- Separate DB-User für App (kein DROP/CREATE-Recht in Prod)

### Tenant Isolation
- Alle Queries MÜSSEN `WHERE tenant_id = ?` enthalten
- `tenantMiddleware` extrahiert tenant_id aus JWT — nie aus Request-Body
- Automatisierter Isolationstest: nach jedem Deploy prüfen (siehe Testing)

---

## 9. Compliance

| Bereich | Anforderung | Umsetzung |
|---------|-------------|-----------|
| GoBD | Keine Löschung Finanzdaten | Soft-delete, Storno als Gegenbuchung |
| GoBD | Audit-Log | `audit_log` append-only, DB-User nur INSERT |
| GoBD | 10 Jahre Aufbewahrung | `tenants.data_retention_until`, Backup, kein Löschen nach Kündigung |
| GoBD | Bon-Nummern lückenlos | `receipt_sequences` mit FOR UPDATE, voided-Status dokumentiert |
| GoBD | Kassensitzungen | `cash_register_sessions` + Z-Bericht in `z_reports` (INSERT-only) |
| GoBD | Täglicher Z-Bericht | Cron-Job warnt bei >24h offener Session |
| GoBD | Preisänderungen nachvollziehbar | `product_price_history` (INSERT-only, kein UPDATE auf price_cents) |
| KassenSichV | TSE-Signatur | Fiskaly Cloud-TSE, offline Queue mit Idempotenz |
| KassenSichV | Bon-Pflichtfelder | Vollständige Liste in Abschnitt 5, inkl. `device_name`/`device_id` |
| KassenSichV | Fortlaufende Bon-Nr. | `receipt_sequences` pro Tenant, nie zurücksetzen |
| KassenSichV | ELSTER-Meldung | Jede neue TSS beim Finanzamt melden — Workflow im Onboarding |
| KassenSichV | TSE-Ausfall >48h | Automatische Benachrichtigung + `tse_outages`-Dokumentation |
| DSGVO | Datenspeicherung DE | Hetzner Frankfurt |
| DSGVO | AVV | Auto-generiertes PDF im Onboarding |
| DSFinV-K | Datenmodell | Ab Phase 1 kompatibel — Export-Endpoint Phase 2 |
| Verfahrensdoku | Pflicht pro Kasse | Muss VOR erstem produktiven Einsatz vorliegen (nicht optional!) |

### Datenhaltung nach Kündigung (GoBD 10 Jahre)
```
Problem: Sofortige Datenlöschung nach Abo-Kündigung = GoBD-Verletzung

Fristberechnung (§ 257 HGB / GoBD):
- Frist beginnt am ENDE DES KALENDERJAHRES der letzten Transaktion
- NICHT ab Kündigungsdatum

Beispiel:
  Letzte Transaktion: 10.03.2026
  → data_retention_until = 31.12.2036 (31.12. des TX-Jahres + 10 Jahre)
  NICHT: 10.03.2036 oder Kündigungsdatum + 10 Jahre

Implementierung:
  data_retention_until = DATE(CONCAT(YEAR(last_transaction_at) + 10, '-12-31'))

Konzept:
1. Bei Kündigung: status='cancelled', data_retention_until berechnen (s.o.)
2. Daten bleiben in DB, Tenant-Zugang gesperrt
3. 30-Tage-Fenster: Tenant kann ZIP-Export selbst anfordern
4. Nach 30 Tagen: nur Lese-Zugriff via Support für Finanzamt-Anfragen
5. Nach data_retention_until: Anonymisierung (Finanzdaten-Struktur bleibt, personenbez. Daten weg)
6. Storage-Kosten: ~5-10MB pro aktivem Monat, 10 Jahre = überschaubar
```

### ELSTER-Meldung neuer Tenants
```
Workflow im Onboarding (nach Stripe-Payment):
1. Fiskaly TSS automatisch erstellen ✓
2. Onboarding-Checkliste zeigt:
   □ "Neue Kasse beim Finanzamt melden" — mit Link zu ELSTER-Portal + Anleitung
   □ AVV unterschreiben
   □ Verfahrensdokumentation herunterladen (auto-generiertes PDF mit Betriebsdaten)
   □ Steuerberater informieren
3. Ohne Abschluss aller Pflicht-Checkboxen: kein Zugang zur Kassen-Funktion
```

---

## 10. Onboarding-Flow

**Implementiert in Phase 3.** Design-Entscheidung: Tenant wird sofort bei Registrierung angelegt
(nicht erst nach Stripe-Webhook), damit der erste Login ohne Polling möglich ist.

```
1. POST /onboarding/register (öffentlich, 3/min/IP):
   - Tenant + Owner-User + erstes Gerät + receipt_sequences in einer DB-Transaktion
   - subscription_status = 'trial' (14 Tage ab created_at, subscriptionMiddleware prüft via created_at)
   - Gibt vollständiges JWT zurück (userId + tenantId + deviceId) — sofortiger Login

2. POST /onboarding/create-checkout-session (auth erforderlich):
   - Stripe Customer anlegen (stripe.customers.create), stripe_customer_id speichern
   - Checkout-Session mit Plan-Preis-ID zurückgeben (success_url / cancel_url vom Client)
   - Umleitung zu Stripe Checkout

3. Stripe Webhook (checkout.session.completed / customer.subscription.created):
   - subscription_status = 'active', Plan setzen, stripe_subscription_id speichern
   - Idempotenz via stripe_events-Tabelle

4. App-Erstkonfiguration (Setup-Wizard — SwiftUI):
   a. Betriebsdaten verifizieren (Name, Adresse, Steuernummer, USt-ID)
   b. Kassensitzung eröffnen (Pflicht: Anfangsbestand eingeben)
   c. Produkte + Kategorien anlegen
   d. Tische + Zonen anlegen (optional bei Schnellverkauf-Betrieb)
   e. TSE-Test: Testbon erstellen und anzeigen

5. Pflicht-Checkliste (BLOCKIERT Produktivbetrieb):
   ☑ Finanzamt-Meldung (ELSTER) — bestätigt mit Datum
   ☑ AVV unterschreiben (in App, mit Timestamp)
   ☑ Verfahrensdokumentation heruntergeladen (auto-generiertes PDF)
   ☑ Steuerberater informiert (Selbstauskunft)
```

**Neue DB-Tabelle:** `stripe_events (id VARCHAR PRIMARY KEY, processed_at DATETIME)` — Webhook-Idempotenz.
**Neue Spalte:** `tenants.subscription_current_period_end DATETIME` — aus invoice.payment_succeeded.

---

## 11. Error Handling — Kritische Edge Cases

### Bon-Nummern-Lücke bei Rollback
```
Problem: Nummer vergeben → Transaktion schlägt fehl → Lücke in Bon-Nummern = GoBD-Problem

Lösung:
1. Nummer aus receipt_sequences holen (FOR UPDATE)
2. Receipt sofort mit status='voided' + void_reason='transaction_failed' anlegen
3. Bei Erfolg: status='active'
4. Lücke ist dokumentiert → GoBD-konform
```

### TSE-Idempotenz bei Timeout
```
Problem: finish-Request sendet → Timeout → erneuter Request → 409 (bereits abgeschlossen)

Lösung:
1. idempotency_key = UUID, wird mit TSE-Transaktion gespeichert
2. Bei Fehler: GET /tx/{tx_id} prüfen ob status="FINISHED"
3. Wenn ja: vorhandene Signatur-Daten verwenden (kein neuer TX)
4. Recovery-Funktion in offline_queue für diesen Fall implementieren
```

### Offline-Queue Verarbeitung
```
- FIFO-Reihenfolge wichtig (chronologische Bon-Nummern-Reihenfolge)
- Exponential Backoff: 1s, 2s, 4s, 8s... max 5 Versuche
- Nach 5 Fehlern: status='failed', manuelle Intervention nötig
- Dashboard-Alert für Owner bei failed-Einträgen
```

---

## 12. Testing-Strategie

**Framework: Vitest** (nicht Jest)
- Nativ TypeScript, kein `ts-jest` nötig
- Gleiche API wie Jest — kein Umlernen
- Schneller (parallel, kein Transpile-Overhead)
- `vitest ui` für visuelles Dashboard

```bash
npm install -D vitest @vitest/coverage-v8 supertest @types/supertest
```

### Test-Typen und Struktur

```
src/__tests__/
├── unit/           -- keine externen Dependencies
│   └── vatCalculation.test.ts  -- MwSt-Berechnung (calcVat, buildVatBreakdown)
├── integration/    -- Vitest + Supertest + echter MariaDB Test-DB
│   ├── auth.test.ts
│   ├── cancellations.test.ts
│   ├── devices.test.ts
│   ├── export.test.ts           -- DSFinV-K Export (503/422/401, kein Fiskaly-Mock)
│   ├── mixed-payments.test.ts
│   ├── modifierGroups.test.ts
│   ├── offline-queue.test.ts
│   ├── onboarding.test.ts
│   ├── orders.test.ts
│   ├── payments.test.ts
│   ├── products.test.ts
│   ├── receipts.test.ts
│   ├── receipts-list.test.ts    -- GET /receipts (Liste, Filter, Plan-Limit)
│   ├── reports.test.ts          -- GET /reports/daily + /summary
│   ├── sessions.test.ts
│   ├── split-bill.test.ts
│   ├── stripe-webhooks.test.ts  -- Stripe Webhook + Idempotenz
│   ├── tables.test.ts
│   ├── tenants.test.ts
│   └── users.test.ts
│   -- Tenant-Isolation-Tests sind in jeder dieser Dateien als eigene
│   -- it()-Blöcke enthalten (nicht als separates compliance-File)
├── compliance/     -- immer grün, kein Merge wenn rot
│   └── receipt-fields.test.ts  -- KassenSichV + GoBD + §14 UStG Pflichtfelder
│                                   (validateReceiptFields + buildReceiptData)
└── external/       -- nightly only (Fiskaly Sandbox)
    └── fiskaly.test.ts
```

### Unit Tests — was genau
- `subtotal_cents`: `(product_price + SUM(modifier_deltas)) × quantity - discount`
- MwSt-Aufschlüsselung: Netto/Brutto korrekt getrennt
- receipt_sequences Logik: Lücken als voided dokumentiert
- Zod-Schemas: valid/invalid inputs für jede Route
- Bon-Pflichtfeld-Checker: alle Felder aus Abschnitt 5 vorhanden?
- Split-Bill: alle Splits summieren = Order-Gesamtbetrag?
- [Phase 3+] Trinkgeld-Berechnungen

### Integration Tests — DB-Strategie
```typescript
// DB-Transaction pro Test → Rollback nach jedem Test
// Kein Truncate nötig, Tests isoliert und schnell
beforeEach(() => db.beginTransaction())
afterEach(() => db.rollback())
```

### Compliance Tests — 100%, nicht verhandelbar
```typescript
// Tenant-Isolation: für JEDEN gesicherten Endpoint
// Tenant A erstellt Ressource → Tenant B greift zu → muss 404 oder 403 sein
const endpoints = ['/orders', '/receipts', '/products', ...]
for (const endpoint of endpoints) {
  it(`${endpoint}: Tenant B sieht keine Daten von Tenant A`, ...)
}
```

### Externe Tests — nightly
- Fiskaly Sandbox: kompletter TSE-Flow + Idempotenz-Recovery
- Stripe CLI: `stripe listen --forward-to localhost:3000/webhooks/stripe`

### CI-Pipeline
```
Jeder Push/PR:    unit + compliance (< 30s) → integration (< 2min) → lint + typecheck
Nightly:          external (Fiskaly + Stripe)
```

### Coverage-Ziele
| Suite | Ziel |
|-------|------|
| Unit (Berechnungslogik) | 90%+ |
| Integration (Endpoints) | alle Endpoints abgedeckt |
| Compliance | 100% — kein Merge wenn rot |

---

## 13. Infrastruktur

### Deployment
- **Staging-Umgebung:** Pflicht vor jedem Prod-Deploy (gleiche Config, Fiskaly Sandbox)
- **Zero-Downtime:** PM2 cluster mode + Rolling Restart (Kassensoftware kann nicht einfach down sein)
- **CI/CD:** GitHub Actions — Test → Lint → Build → Deploy Staging → Smoke Test → Deploy Prod
- **DB-Migrations-Tool:** Flyway oder db-migrate — automatisch bei Deploy, mit Rollback

### Backup
- Hetzner Volumes: tägliches automatisches Snapshot
- Offsite: wöchentlicher Dump zu Hetzner Object Storage (S3-kompatibel, DE-Region)
- Verschlüsselung: AES-256 vor Upload
- Restore-Test: monatlich (Tabletop-Test)
- Aufbewahrung: 10 Jahre (GoBD-Pflicht)

### Monitoring & Alerting
- **TSE-Fehler:** sofortiger Alert an Owner + Admin
- **Offline-Queue > 10 Einträge:** Warning
- **Webhook-Fehler (Stripe):** Alert
- **TSE-Ausfall > 48h:** E-Mail Pflichtbenachrichtigung (KassenSichV)
- Tool: Betterstack / UptimeRobot für Basics + eigene Logging-Middleware

### Admin-Panel (ab zweitem Kunden)
- Tenant-Übersicht (Status, Plan, letzte Aktivität)
- Support-Zugriff (read-only auf Tenant-Daten)
- Plan-Override, manueller Subscription-Reset
- Offline-Queue-Status pro Tenant

---

## 14. SaaS-Betrieb

### Plan-Limits (muss definiert werden)
| Limit | Starter | Pro | Business |
|-------|---------|-----|----------|
| Geräte | 1 | 3 | 10 |
| Tische | 10 | 30 | unbegrenzt |
| Produkte | 50 | 200 | unbegrenzt |
| Berichte | 30 Tage | 1 Jahr | 10 Jahre |

### Churn-Prozess
```
1. Kündigung: status='cancelled', subscription läuft bis Periodenende
2. Danach: Zugang gesperrt, Daten bleiben (data_retention_until)
3. 30-Tage-Fenster: Tenant kann ZIP-Export seiner Daten anfordern
4. Nach 30 Tagen: nur noch Lese-Zugriff für Finanzamt-Anfragen (via Support)
5. Nach data_retention_until (10 Jahre): Anonymisierung
```

### SaaS-Rechnungen
- Stripe-Belege reichen NICHT für deutsche Buchführungspflicht
- Eigene Rechnungs-PDFs generieren (mit korrekter MwSt-Ausweisung)
- Tool: Stripe Invoicing (konfigurierbar) oder eigengebaut mit deutschen Pflichtfeldern

### App-Versionszwang
```
-- devices-Tabelle:
min_app_version VARCHAR  -- Backend-seitig konfigurierbar

-- App-Header bei jedem Request:
X-App-Version: 1.2.3

-- versionMiddleware prüft:
if appVersion < min_app_version → 426 Upgrade Required
```

---

## 15. Entwicklungsphasen (aktualisiert)

| Phase | Inhalt | Deliverable |
|-------|--------|-------------|
| **Phase 0** | Fiskaly Sandbox testen, SwiftUI lernen, Steuerberater, AGB, Testing-Setup | Fundament |
| **Phase 1** (Monat 1-2) | Backend: Auth + Produkte + Tische + Bestellungen + Kassensitzungen (kein TSE) | SwiftUI MVP, digitaler Bon ohne TSE, DSFinV-K-Datenmodell vorhanden |
| **Phase 2** (Monat 3) | Fiskaly TSE + Receipts mit allen Pflichtfeldern + Storno + Split Bill + Gemischte Zahlung + Z-Bericht | TSE-konformer digitaler Bon |
| **Phase 3** (Monat 4) ✅ | Stripe Abo + Onboarding (Register+Checkout+Webhook) + Trial-Logik (14 Tage) + Offline-Queue + Pilotkunde | Produktiveinsatz Shishabar |
| **Phase 4** (Monat 5-6) ✅ Backend | DSFinV-K Export (✅) + Reports (✅) + Admin-Panel (❌ noch offen) + erste zahlende Kunden | Recurring Revenue |
| **Phase 5** (Monat 7+) | Bondrucker (StarIO) + Multi-iPad Sync + DATEV-Export | Skalierung |

> **App Store:** Einreichung spätestens 4-6 Wochen vor geplantem Go-live (Review kann 1-4 Wochen dauern).
> Bei Finanzapplikationen eher konservativ planen.

---

## 16. Offene TODOs vor Phase 0

*(Diese Liste stammt aus der ursprünglichen Planung — viele Punkte inzwischen erledigt)*

- [ ] Fiskaly Sandbox Account anlegen — Transaktionsflow durchspielen
- [ ] Steuerberater: Offline-TSE-Handling absegnen lassen
- [ ] Steuerberater: Trinkgeld-Verbuchung klären — erst vor Phase 3 nötig (Feature bis dahin deaktiviert)
- [ ] Steuerberater: Außer-Haus-MwSt klären — erst vor Phase 4 nötig (für Shishabar-Pilot irrelevant)
- [ ] AGB + Haftungsausschluss (Anwalt, ~300-500€)
- [ ] AVV-Vorlage erstellen
- [ ] Verfahrensdokumentation-Vorlage erstellen (vor Go-live Pflicht!)
- [ ] Apple Developer Account (99€/Jahr) für TestFlight
- [ ] Gewerbeanmeldung falls noch nicht vorhanden
- [ ] Schriftliche Vereinbarung mit Pilotkunden
- [x] Testing-Framework festlegen → Vitest + Supertest ✅
- [ ] Datenhaltungs-Konzept nach Kündigung kommunizieren (AGB-relevant)
- [ ] `receipt_sequences` Konzept mit Steuerberater besprechen (Lücken-Dokumentation)

---

## 17. Offene Backend-Punkte (nach Vollständigkeitsprüfung)

### Kritisch — vor Go-live

**E-Mail-Service (kein Transactional-Mail implementiert)**
Wird benötigt für:
- TSE-Ausfall > 48h → Pflichtbenachrichtigung (KassenSichV)
- Trial-Ablauf-Warnung (z.B. 7 Tage vorher)
- Session > 24h offen → Warnung an Owner (GoBD)
- Passwort-Reset-Flow

Empfehlung: Resend oder Postmark (einfache REST-API, keine SMTP-Konfiguration).

**Cron-Jobs (komplett fehlend)**
Im Plan erwähnt, in DB-Schema vorbereitet (`tse_outages`-Tabelle), aber nie implementiert:
```
Täglich:
  - Sessions prüfen die > 24h offen → E-Mail an Owner (GoBD-Warnung)
  - TSE-Ausfall-Status prüfen → nach 48h: E-Mail + tse_outages.notified_at setzen
Stündlich:
  - Offline-Queue auf 'failed'-Einträge prüfen → Alert (Dashboard + E-Mail)
```
Umsetzung: `node-cron` oder PM2-Cron-Task. Separates Script `src/cron.ts` das neben `index.ts` läuft.

**`POST /auth/forgot-password` + `POST /auth/reset-password` fehlen**
Ohne Passwort-Reset kein Self-Service-Recovery. Wenn Owner Passwort vergisst → manueller DB-Eingriff nötig.
Flow: Token per E-Mail → Link → neues Passwort setzen (Token einmalig, 1h gültig).

**`versionMiddleware` nicht implementiert**
DB-Feld `devices.min_app_version` vorhanden, Middleware fehlt.
```typescript
// X-App-Version Header aus App → semver-Vergleich → 426 wenn veraltet
if (semver.lt(appVersion, minAppVersion)) → 426 Upgrade Required
```

**`GET /tenants/me` gibt keine Subscription-Details zurück**
Frontend hat keine Info über Trial-Restzeit oder `subscription_current_period_end`.
Ergänzen: `trial_expires_at`, `subscription_current_period_end`, `subscription_status` in Response.

### Wichtig — nach Pilot

**ELSTER-Onboarding-Checkliste nicht durchgesetzt**
Plan sieht vor: Kassen-Features gesperrt bis Checklist abgehakt (ELSTER-Meldung, AVV, Verfahrensdoku).
Datenmodell fehlt (z.B. `tenants.onboarding_completed BOOLEAN`). Ohne Enforcement kann ein Tenant die Kasse nutzen ohne die Pflichten erfüllt zu haben.

**Tenant-Daten-Export nach Kündigung fehlt**
Plan: 30-Tage-Fenster für ZIP-Export nach Kündigung (`subscription_status = 'cancelled'`).
Weder Endpoint (`POST /tenants/me/export`) noch Hintergrund-Job implementiert.

**Rate-Limit per Tenant statt per IP**
Aktuell: `apiRateLimit` läuft vor `authMiddleware` → effektiv per IP.
Nachteil: Tenant hinter NAT/Proxy kann andere Tenants blockieren.
Lösung: `apiRateLimit` nach `tenantMiddleware` verschieben, `keyGenerator: req.auth.tenantId`.

### Nice-to-have

**Structured Logging**
Aktuell: nur `console.error` im Error-Handler.
Produktion braucht JSON-Logs mit Request-ID, Tenant-ID, Dauer (Winston oder Pino).

**Graceful Shutdown**
Kein `SIGTERM`-Handler — bei PM2 Rolling Restart können laufende TSE-Transaktionen abbrechen.
```typescript
process.on('SIGTERM', async () => {
  await db.end(); // Pool-Connections sauber schließen
  server.close(() => process.exit(0));
});
```

**`.env.example` fehlt**
Kein Template für Environment-Variablen. Neues Deployment ohne Dokumentation was zu setzen ist.

---

## 18. Nächste Schritte (priorisiert)

### Diese Woche — Blocker für Pilot

1. **SwiftUI starten** — kritischer Pfad, alles andere ist zweitrangig
   Reihenfolge: `LoginView` → `SessionView` → `TableOverviewView` → `OrderView` → `PaymentView` → `ReceiptView`
   ModifierSheet, SplitBill, ReportsView danach.

2. **E-Mail-Service + Cron-Jobs** — KassenSichV-Pflicht
   TSE-Ausfall-Meldung nach 48h ist gesetzlich vorgeschrieben. Muss vor Produktiveinsatz laufen.

3. **`versionMiddleware`** — klein (~2h), aber nötig sobald erste App-Version deployed

4. **`.env.example`** — 30 Minuten, verhindert Fehler beim Deployment

### Vor Go-live — nicht optional

5. **Rechtliches**: AGB, AVV, Verfahrensdokumentation (Anwalt beauftragen)
6. **Infrastruktur**: Hetzner-Server, GitHub Actions CI/CD, Nginx, SSL, PM2
7. **Fiskaly Live-Account** anlegen + TSS für Shishabar + ELSTER-Meldung
8. **Stripe Live-Keys** + Webhook-Endpoint in Stripe-Dashboard eintragen
9. **Passwort-Reset-Flow** implementieren
10. **Apple Developer Account** (99€/Jahr) für TestFlight-Verteilung

### Nach Pilot

11. ELSTER-Onboarding-Checkliste enforcement
12. Tenant-Daten-Export (ZIP nach Kündigung)
13. Rate-Limit per Tenant
14. Structured Logging (Pino/Winston)
15. Graceful Shutdown
16. `GET /tenants/me` Subscription-Details ergänzen

---

*Plan-Version: 2.4 | Stack: SwiftUI / Node.js+TS / MariaDB / Fiskaly / Stripe*
*Scope Phase 1-4: Digitaler Bon (kein Drucker), Single-iPad (kein Multi-Device-Sync)*
*Trinkgeld: deaktiviert bis Phase 3 | Außer-Haus-Toggle: deaktiviert bis Phase 4*

---

## Changelog

| Version | Änderung |
|---------|----------|
| 1.0 | Initiale Version |
| 2.0 | Gap-Analyse eingearbeitet: receipt_sequences, cash_register_sessions, cash_movements, Split Bill, Rabatte, Security, Testing, Infrastruktur |
| 2.1 | KassenSichV-Fachprüfung: `receipts.device_id/device_name` (§6 KassenSichV), 10-Jahres-Frist-Korrektur (Ende Kalenderjahr), `z_reports` als INSERT-only-Tabelle, 24h-Session-Warnung, `product_price_history`, Trinkgeld-TSE-Schema korrigiert, MVP-Scoping für Trinkgeld und Außer-Haus |
| 2.2 | Produktvarianten / Modifikatoren: `product_modifier_groups`, `product_modifier_options`, `order_item_modifiers`, API-Endpunkte, SwiftUI ModifierSheet, Bon-Darstellung |
| 2.3 | Logik-Konsistenzprüfung: `receipts.tip_cents` wiederhergestellt, `products.updated_at` korrigiert (nur price_cents immutable), `product_modifier_groups.is_active` ergänzt, Trinkgeld/Außer-Haus im UI als Phase-markiert, doppelter Z-Bericht-Endpoint bereinigt, `sessionMiddleware` ergänzt, Modifier-Tenant-Validierung dokumentiert |
| 2.5 | Vollständigkeitsprüfung: Abschnitte 17 (offene Backend-Punkte) und 18 (priorisierte nächste Schritte) ergänzt. TypeScript-Fehler behoben (`exportController`, `receiptsController`, `rateLimitMiddleware`). TS-Build sauber. |
| 2.4 | Phase 4 Backend vollständig: `GET /receipts` (Liste + Plan-Limit), `GET /reports/daily` + `/summary` (Plan-Limit Starter/Pro/Business), `GET /export/dsfinvk` + `/:id/status` + `/:id/file` (Fiskaly TAR-Proxy, async mit 202-Fallback). Fiskaly-Doku ausgewertet (SIGN_DE_V2_API-DOC.json): `start_date`/`end_date` als Unix-Timestamps, Polling auf PENDING→COMPLETED, TAR-Format. Teststruktur aktualisiert (20 Integration-Testdateien, 302 Tests). |

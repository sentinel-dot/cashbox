Prüfe den aktuellen Go-Live-Status des Kassensystems und erstelle eine priorisierte Checkliste was noch fehlt.

## Was du prüfst

Gehe jeden Punkt durch und bestimme anhand des aktuellen Codes + CLAUDE.md ob er erledigt ist.

---

### 🔴 Sicherheit — blockiert Go-Live

- [ ] **Refresh-Token-Type-Check** — `authMiddleware.ts`: prüft `(payload as any).type === 'refresh'`?
- [ ] **`past_due` Grace Period** — `subscriptionMiddleware.ts`: wird nach Ablauf tatsächlich geblockt (402)?

### 🔴 SwiftUI Pflicht-Screens — ohne diese ist die App unbrauchbar

- [ ] `SessionStore` implementiert
- [ ] `OrderStore` implementiert
- [ ] `KassensitzungView` (Session öffnen/schließen) — ohne das kein Kassenbetrieb
- [ ] `TableOverviewView` — Tischübersicht
- [ ] `OrderView` — Bestellung aufnehmen
- [ ] `ModifierSheet` — Pflichtauswahl für Produkte mit required Modifier-Gruppen
- [ ] `PaymentView` — Zahlung abschließen (Bar/Karte/Gemischt)
- [ ] `ReceiptView` — digitaler Bon anzeigen

### 🔴 Backend Pflicht-Features — KassenSichV/gesetzlich

- [ ] **E-Mail-Service** (Resend oder Postmark): TSE-Ausfall >48h → E-Mail an Owner ist KassenSichV-Pflicht
- [ ] **Cron-Jobs**: täglich Session >24h prüfen, TSE-Ausfall >48h prüfen, Offline-Queue-Fehler prüfen
- [ ] **Passwort-Reset** (`POST /auth/forgot-password` + `/reset-password`) — ohne das kein Self-Service

### 🟡 Backend — vor echtem Produktiveinsatz

- [ ] **`versionMiddleware`** — `X-App-Version` Header prüfen, 426 wenn veraltet
- [ ] **`GET /tenants/me`** gibt `trial_expires_at` + `subscription_current_period_end` zurück (Frontend braucht das für Trial-Anzeige)

### 🟡 Infrastruktur

- [ ] Hetzner-Server provisioniert (Ubuntu, Node.js, MariaDB, Nginx, PM2)
- [ ] GitHub Actions CI/CD eingerichtet (Test → Build → Deploy Staging → Deploy Prod)
- [ ] SSL-Zertifikat (Let's Encrypt via Certbot)
- [ ] Fiskaly Live-Account + TSS für Shishabar angelegt
- [ ] Stripe Live-Keys + Webhook-Endpoint eingetragen
- [ ] Automatische Backups (Hetzner Volume Snapshots täglich)

### 🟡 Rechtliches (vor Produktiveinsatz Pflicht)

- [ ] AGB + Haftungsausschluss (Anwalt)
- [ ] AVV (Auftragsverarbeitungsvertrag) — DSGVO-Pflicht
- [ ] Verfahrensdokumentation erstellt (vor Go-Live Pflicht, KassenSichV)
- [ ] ELSTER-Meldung: neue TSS beim Finanzamt angemeldet
- [ ] Apple Developer Account (99€/Jahr) für TestFlight

### 🟢 Empfohlen — bald nach Go-Live

- [ ] Error-Monitoring (Sentry) — Free Tier, ~20min
- [ ] Graceful Shutdown (`SIGTERM`-Handler in `index.ts`)
- [ ] Docker Compose für lokale Entwicklung

---

## Wie du vorgehst

1. Lese `CLAUDE.md` Implementierungsstand (Frontend + Backend)
2. Für jeden ❌-Punkt in der Checkliste: kurz erklären was noch fehlt und wie aufwändig
3. Ausgabe: Tabelle mit Status (✅ / ❌ / ⚠️ teilweise), Aufwand-Schätzung, nächster Schritt

Fasse am Ende zusammen: Wie viele Punkte fehlen noch, was ist der kritische Pfad zum Pilot?

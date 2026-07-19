# ROADMAP — Abarbeitung bis Go-live (Session für Session)

**Zweck:** Der komplette Weg von heute (Test-Offensive fertig, Pilot startklar) bis Go-live —
aufgeteilt in Pakete, von denen **eines pro Claude-Session** umgesetzt wird. Kein Paket überspringen,
kein Gate ignorieren. Was ein Paket *inhaltlich* bedeutet, steht in `OFFEN.md` (bleibt die einzige
Quelle für offene Punkte); hier stehen Reihenfolge, Session-Prompts und Abnahmekriterien.

**Stand:** 2026-07-19 · Suiten: Backend 84 Unit/Compliance + 304 Integration, iOS 40 XCTests — alle grün.
Backend-Suiten laufen seit S01 als PR-Gate in GitHub Actions (`docs/ci.md`); `main` ist geschützt.

---

## Arbeitsregeln für jede Session (immer, keine Ausnahme)

1. **Ein Paket pro Session.** Nicht zwei anfangen, nicht „wo wir gerade dabei sind" erweitern.
   Neue Erkenntnisse → als neuen Punkt mit Prio in `OFFEN.md`, nicht sofort bauen.
2. **Session-Start:** `git status` sauber, dann `npm test` + `npm run test:integration` (backend/) —
   erst arbeiten, wenn grün. Bei größeren Paketen (≥ 1 Tag) mit `/plan` starten.
3. **Session-Ende (Definition of Done, global):**
   - [ ] Alle Suiten grün (Backend + ggf. iOS `xcodebuild test`)
   - [ ] Neue Logik: pure Funktion + Unit-Test (Muster: `validateSplitPartition`), neue Route:
         Integrationstest + Tenant-Isolation-`it()` (CLAUDE.md-Pflicht)
   - [ ] `docs/testkonzept.md`: neue REQ/TC eingetragen, Traceability ergänzt
   - [ ] `OFFEN.md` gestrichen/angepasst, `CLAUDE.md`-Implementierungsstand aktualisiert
   - [ ] Hier in `ROADMAP.md` das Paket abgehakt
   - [ ] Committet (kleine, thematische Commits)
4. **Kritische Regeln aus `CLAUDE.md` gelten immer** (Cent-Integer, kein DELETE/UPDATE auf
   Finanzdaten, tenant_id nur aus JWT, Session-Lock-Invariante, Zod auf jeder Route).
5. **Session-Prompt:** Den Prompt aus dem jeweiligen Paket kopieren — er enthält den nötigen Kontext.

---

## Zur Audit-Frage („Angst wegen Finanzamt/Fiskaly")

Die Angst geht nicht durch weitere Voll-Audits weg — der bestehende Code ist nach 2 Audits +
Test-Offensive dreifach abgesichert (Unit/Integration/E2E + Race-Tests); ein drittes generisches
Audit auf unverändertem Code bringt fast nichts mehr. Was sie wirklich beseitigt:

| Struktur-Maßnahme | Warum sie Angst ersetzt | Paket |
|---|---|---|
| **CI als PR-Gate** | „Getestet" wird Dauerzustand statt Momentaufnahme — jede Änderung muss durch 418+ Tests | S01/S02 |
| **Sentry** | Fehler in Produktion sehen, bevor der Wirt anruft | S03 |
| **Backup + Restore-Test** | GoBD verlangt 10 Jahre; ungetestetes Backup ist keins | S11 |
| **Gezielte Audits an Gates** | Audits dort, wo *neuer* Code scharf geht — nicht pauschal | S15, S19 |
| **Steuerberater + amtliche Prüfsoftware** | Das Finanzamt-Gate nimmt am Ende nicht Claude ab, sondern der Steuerberater mit dem DSFinV-K-Prüftool | S17 |

**Audit-Regel ab jetzt:** Fable-Audits folgen Meilensteinen (neue Integration wird scharf), nicht dem
Bauchgefühl. Geplant sind genau zwei: **#3 TSE/Fiskaly** (vor Fiskaly-Live, S15) und
**#4 Security/Auth/Stripe** (vor öffentlichem Go-live, S19). Jedes Audit endet mit Fixes **und**
daraus abgeleiteten Regressionstests — kein Audit ohne Test-Niederschlag.

---

# Meilenstein 0 — Fundament (dann Pilot starten)

**Gate M0:** CI blockt rote PRs nachweislich · Sentry empfängt Test-Event · App via TestFlight auf dem Pilot-iPad.

## [x] S01 — CI Backend (GitHub Actions) — erledigt 2026-07-19
**Prompt:**
> Setze Paket S01 aus ROADMAP.md um: GitHub-Actions-Workflow als PR-Gate für main.
> Job 1: backend/ — Node LTS, `npx tsc --noEmit`, `npm test`, `npm run test:integration` mit
> MariaDB-Service-Container (DB-Setup nach dem Muster von `backend/scripts/setup-db.ts` /
> `npm run db:setup:test`; Achtung: Timezone-Tabellen laden, sonst liefern Report-Tests 0 —
> siehe CLAUDE.md Betriebshinweis). Secrets/Env dokumentieren. Teste den Workflow, indem du
> einen absichtlich kaputten Test in einem Branch pushst und zeigst, dass der PR rot wird.

**DoD:** Workflow läuft auf Push/PR; roter Test → roter PR (nachgewiesen); README-Badge optional.

**Erledigt 2026-07-19:** `.github/workflows/ci.yml` (Job `backend`, MariaDB-11.4-Service-Container,
tzinfo laden + Guard, `tsc --noEmit` → `db:setup:test` → `npm test` → `test:integration`).
`setup-db.ts` nimmt jetzt `DB_USER_HOST` (Default `localhost`, CI `%`) — sonst greifen die Grants im
Service-Container nicht. Nachweis auf PR #1: Run `29702114397` rot (absichtlicher Assert-Fehler,
Check `failure`), Run `29702157037` grün (76 + 301 Tests). Branch Protection auf `main` aktiv
(Required Check + kein Force-Push). Doku: `docs/ci.md`. Kein Badge (kein README im Repo).

## [x] S02 — CI iOS — erledigt 2026-07-19
**Prompt:**
> Setze Paket S02 aus ROADMAP.md um: zweiter GitHub-Actions-Job auf macos-Runner:
> `xcodebuild test -project zettel-frontend/zettel-frontend.xcodeproj -scheme zettel-frontend`
> gegen einen iPad-Simulator (Destination dynamisch wählen, Runner-Simulatoren variieren).
> Der Job ist Teil desselben PR-Gates.

**DoD:** iOS-Tests laufen in CI; kaputter Swift-Test → roter PR.

**Erledigt 2026-07-19:** Job `ios` in `.github/workflows/ci.yml` auf `macos-26`, Destination zur
Laufzeit per `simctl --json` + `jq` (neueste iOS-Runtime → erstes iPad). Geteiltes Xcode-Scheme
committet (Voraussetzung — `xcuserdata/` ist gitignored). Nachweis auf PR #2: Run `29702799713`
grün (40 Tests), Run `29703020329` rot bei absichtlich kaputtem XCTest, Backend-Job im selben Lauf
grün. Beide Checks in der Branch Protection. **Neuer Befund → `OFFEN.md` T7:** Test-Target verlangt
iOS 26.2, App nur 18.2 — bindet CI ans Preview-Image `macos-26`, vor S04 zu klären.

## [x] S03 — Sentry + Prozess-Härtung (S1 + B6 + B7) — erledigt 2026-07-19
**Prompt:**
> Setze Paket S03 aus ROADMAP.md um (OFFEN.md S1, B6, B7): (1) `@sentry/node` einbauen,
> captureException im globalen Error-Handler in `backend/src/app.ts`, Tenant aus JWT als Tag,
> DSN via env. (2) `backend/src/index.ts`: SIGTERM-Handler (Server drainen, beide DB-Pools
> schließen), `unhandledRejection`/`uncaughtException`-Handler (loggen + kontrolliert beenden),
> console.* durch Pino (`src/logger.ts`) ersetzen. (3) `.env.example`: ALLOWED_ORIGIN,
> LOG_LEVEL, SENTRY_DSN ergänzen.

**DoD:** Test-Event in Sentry sichtbar; `kill -TERM` beendet sauber (Log zeigt Drain); Suiten grün.

**Erledigt 2026-07-19:** `src/sentry.ts` (`@sentry/node` v10 — nur 5xx, Tags tenant/method/source,
keine PII; ohne `SENTRY_DSN` komplett aus), `src/shutdown.ts` (`createShutdown` mit DI: Drain →
Flush → Pools, idempotent, 10-s-Notbremse), `index.ts` auf Pino + SIGTERM/SIGINT/
unhandledRejection/uncaughtException, `.env.example` um ALLOWED_ORIGIN/LOG_LEVEL/SENTRY_DSN
ergänzt. Auch der fire-and-forget `console.error` im Stripe-Webhook geht jetzt an Log + Sentry
(fehlgeschlagener audit_log-INSERT ist GoBD-relevant). Tests: **+8 Unit** (`unit/shutdown`),
**+3 Integration** (`integration/errorHandler`) → 84 + 304 grün. REQ-OPS-001…004 im Testkonzept.
Nachweise in `docs/betrieb.md`: SIGTERM-Log mit Drain (Exit 0) und Keep-Alive-Fall (42 ms statt
10-s-Notbremse — belegt `closeIdleConnections()`); Sentry-Envelope gegen lokalen Ingest verifiziert.
**DoD vollständig:** Sentry-Projekt in der **EU-Region** (ingest.de.sentry.io) angelegt, DSN
eingetragen, Test-Event am 2026-07-20 im Dashboard sichtbar. Dafür `npm run sentry:test`
(`src/scripts/sentry-test.ts`) — wird bei S20 für Prod wiederverwendet.
**Neue Befunde:** `OFFEN.md` **T8** — `npm run dev` (ts-node/CJS) startet nicht (Bestandsproblem,
nicht angefasst). `OFFEN.md` **T9** — Report-Tests waren nachts 2 h flaky (UTC- statt
Berlin-Datum); im selben Fenster gefunden und behoben, weil ein nachts grundlos rotes PR-Gate
den Wert von S01 untergräbt. Berichtslogik war korrekt, nur die Tests lagen falsch.
**Offen beim User:** Alert-Regel in Sentry setzen; DPA/AVV unter Settings → Legal akzeptieren (N8).

## [ ] S04 — Pilot-Start (User-Aktionen, ohne Claude-Session)
- [x] N7: Apple Developer Account — vorhanden (2026-07-19 bestätigt)
- [ ] TestFlight-Build hochladen, Shishabar-iPad einladen
- [ ] Guided Access auf dem Pilot-iPad einrichten (Kiosk, siehe OFFEN.md §6 Betriebshinweis)
- [ ] Schriftliche Pilot-Vereinbarung (Vorlage: N8) unterschreiben lassen

---

# Meilenstein 1 — Pilotbetrieb & Go-live-Pakete Backend

**Gate M1:** Alle B-Pakete in CI grün · eine echte Z-Bericht-Mail zugestellt · Restore-Test protokolliert · Pilot ≥ 2 Wochen ohne Kassendifferenz-Vorfall.

## [ ] S05 — E-Mail-Service Grundgerüst (B1 Teil 1) — ~1,5 d
**Prompt:**
> Setze Paket S05 aus ROADMAP.md um (OFFEN.md §5): `backend/src/services/email.ts` mit
> Resend (oder Postmark — kurz begründen), Template-Registry, Migration für `email_log`
> (INSERT-only: tenant_id, template, recipient, sent_at, provider_message_id — Grants wie
> audit-Tabellen in setup-db.ts), Retry via Queue-Pattern analog offline_queue. Erstes
> Template: Trial-Warnung (Tag 10+13) im Ledger-Green-Look (Design-Vorgaben in OFFEN.md §5:
> 600px single column, System-Font-Stack, deutsche Beträge wie euroString, Plaintext-Fallback).
> Unit-Test für Template-Rendering (Betrags-/Datumsformat), Integrationstest für email_log.

**DoD:** Mail kommt real an (eigene Adresse); email_log-Zeile geschrieben; Fehlversand → Retry-Eintrag.

## [ ] S06 — E-Mail-Templates komplett (B1 Teil 2) — ~1 d
**Prompt:**
> Setze Paket S06 aus ROADMAP.md um: restliche Templates aus OFFEN.md §5 — TSE-Ausfall >48h
> (Pflichtmeldung: Zeitraum, Gerät, ELSTER-Handlungsanweisung), Passwort-Reset (Token-Link, 1h),
> Z-Bericht-Tageszusammenfassung (opt-in; Umsatz, Zahlarten, Differenz), Subscription-Events
> (past_due, Kündigung + Datenexport-Hinweis, Reaktivierung), Session >24h offen. Je Template:
> Betreff, HTML, Plaintext, Render-Unit-Test. SPF/DKIM/DMARC-Einrichtung als Doku-Abschnitt.

**DoD:** Alle 6 Templates renderbar + getestet; DNS-Anleitung dokumentiert.

## [ ] S07 — Cron-Jobs (B2, inkl. A9) — ~2 d
**Prompt:**
> Setze Paket S07 aus ROADMAP.md um (OFFEN.md B2): `backend/src/cron.ts` (node-cron, läuft
> neben index.ts). Täglich: Trial-Warnung Tag 10+13 (via S05/S06-Templates), past_due-Sperrung
> nach Grace Period, Sessions >24h offen → Owner-Mail, TSE-Ausfall >48h → Meldung +
> `tse_outages.notified_at`. Stündlich: failed-Offline-Queue → Alert; serverseitiger
> Offline-Queue-Drain (Nachsignierung darf nicht vom iPad abhängen — Claim-Muster via
> `processing_started_at` aus V006 nutzen); geschlossene Sessions ohne z_reports-Zeile →
> Alert + Nachtrag (A9). Jeden Job idempotent bauen (doppelter Lauf = kein Doppelversand,
> email_log als Dedup-Quelle). Integrationstests mit Zeit-Fixtures.

**DoD:** Jeder Job einzeln per Test ausgelöst; Doppellauf-Test beweist Idempotenz; A9 in OFFEN.md streichen.

## [ ] S08 — Passwort-Reset (B3) — ~1 d
**Prompt:**
> Setze Paket S08 aus ROADMAP.md um (OFFEN.md B3): `POST /auth/forgot-password` +
> `POST /auth/reset-password`. Token einmalig, 1h gültig, nur gehasht in DB; Rate-Limit;
> immer 200 (kein User-Enumeration-Leak); Mail via S05-Service. Integrationstests inkl.
> abgelaufener/verbrauchter Token und Tenant-Isolation. iOS: „Passwort vergessen"-Link im
> LoginView (DSTextField-Sheet, Du-Anrede).

**DoD:** Kompletter Reset-Flow einmal real durchgespielt (Mail → Link → neues Passwort → Login).

## [ ] S09 — Audit-Reste A3 + A6 (B8) — ~1 d
**Prompt:**
> Setze Paket S09 aus ROADMAP.md um: (1) A3: In `ordersController.addItem` laufen die
> Modifier-INSERTs (auditDb) nach dem Commit — bei Fehler Kompensation schreiben:
> `order_item_removals`-Eintrag für das Item, dann 500 (Begründung in OFFEN.md §1 A3).
> Integrationstest mit gemocktem auditDb-Fehler. (2) A6: in `backend/scripts/setup-db.ts`
> audit_insert_user auf tabellen-scoped INSERT-Grants umstellen (die 5 Tabellen stehen im
> Kommentar dort), inkl. REVOKE-Pfad für Bestands-DBs; Prod-DBA-Anweisung in der Doku anpassen.

**DoD:** A3-Test grün; `SHOW GRANTS` für audit_insert_user zeigt nur die 5 Tabellen; OFFEN.md A3/A6 streichen.

## [ ] S10 — versionMiddleware + Subscription-Details (B4 + B5) — ~1 d
**Prompt:**
> Setze Paket S10 aus ROADMAP.md um: (1) B4: `versionMiddleware` — `X-App-Version`-Header,
> semver gegen `devices.min_app_version` → 426; in die Middleware-Kette laut CLAUDE.md
> einordnen; iOS sendet Version im APIClient und zeigt bei 426 einen Update-Hinweis (Vollbild,
> kein Weiter). (2) B5: `GET /tenants/me` um `trial_expires_at` +
> `subscription_current_period_end` erweitern; iOS EinstellungenView zeigt Trial-Restzeit,
> Banner ab Tag 10. Tests: 426-Pfad, Feld-Decoding-Fixture im iOS-Test-Target.

**DoD:** Alte App-Version wird sauber ausgesperrt (manuell getestet); Trial-Banner sichtbar.

## [ ] S11 — Backup + Restore-Test (N1) — ~0,5 d
**Prompt:**
> Setze Paket S11 aus ROADMAP.md um (OFFEN.md N1, GoBD-Pflicht): Backup-Script (nightly
> mysqldump, Verschlüsselung, Offsite z.B. Hetzner Storage Box, Retention 10 Jahre für
> Finanzdaten), systemd-Timer/Cron-Anleitung, und ein **dokumentierter Restore-Test**:
> Schritt-für-Schritt-Protokoll in docs/, das ich einmal real durchführe (Test-DB aus Dump
> wiederherstellen, Suiten dagegen laufen lassen). Hinweis in die Verfahrensdokumentation (N8).

**DoD:** Restore-Protokoll mit Datum in docs/; Wiederherstellung nachweislich einmal durchgeführt.

## [ ] S12 — Pilot-UX-Paket (aus §6, nach echtem Feedback) — ~1 d
**Prompt:**
> Setze Paket S12 aus ROADMAP.md um — die zwei wichtigsten §6-Punkte aus OFFEN.md plus das,
> was der Pilot real gezeigt hat: (1) Fehler-Alerts mit Retry-Button +
> `AppError.failureReason` als Sekundärzeile (app-weit, alle in OFFEN.md §6 gelisteten Views).
> (2) forceLogout (16h-Limit) darf den Warenkorb nicht verlieren — offenen Order-Zustand
> sichern und nach Re-Login wieder anbieten. Priorisiere um, falls Pilot-Feedback dringlichere
> Punkte ergeben hat (dann OFFEN.md §6 entsprechend umsortieren und hier notieren).

**DoD:** Beide Punkte in OFFEN.md §6 gestrichen; iOS-Tests grün; kurzer Pilot-Feedback-Stand in OFFEN.md notiert.

---

# Meilenstein 2 — TSE scharf (Phase 2)

**Gate M2:** Signierte Bons auf dem Pilot-iPad · Nachsignierung nach simuliertem Ausfall nachweisbar · DSFinV-K vom Steuerberater mit amtlicher Prüfsoftware abgesegnet.

**Vorlauf sofort anstoßen (User):** N9-Termin beim Steuerberater (receipt_sequences-Konzept +
Offline-TSE-Handling absegnen — braucht Wochen Vorlauf), Fiskaly-Live-Account beantragen.

## [ ] S13 — A1 + A2 lösen — ~1,5 d
**Prompt:**
> Setze Paket S13 aus ROADMAP.md um (OFFEN.md §1 A1/A2, Phase-2-Blocker): (1) A1: TSE läuft
> heute vor der DB-TX in payOrder/splitBill/cancelReceipt — verliert die Zahlung das 409-Race,
> existiert eine signierte TSE-TX ohne Bon. Entscheide mit mir per AskUserQuestion zwischen
> „Fiskaly-TX bei Abbruch canceln" und „TSE nach dem Session-Lock" (Lock-Dauer abwägen,
> Fiskaly-Timeout ist 10s) und setze um. (2) A2: Fiskaly-4xx blockiert heute den Verkauf —
> umstellen auf tse_pending + lauten Alert (Mail via S05), Verkauf läuft weiter (KassenSichV
> erlaubt dokumentierten Offline-Betrieb; Begründung OFFEN.md A2). REQ-TSE im Testkonzept
> erweitern, Unit-Tests für beide Pfade (fiskaly-Mock), Integrationstests.

**DoD:** Beide A-Punkte in OFFEN.md gestrichen; Race-Test „TSE-TX ohne Bon" beweist die Lösung.

## [ ] S14 — Fiskaly-Sandbox-E2E in CI — ~0,5 d
**Prompt:**
> Setze Paket S14 aus ROADMAP.md um: `npm run test:external` (Fiskaly-Sandbox) als
> CI-Nightly-Job (Secrets: Sandbox-Keys), mit Alert bei Rot. Sandbox-E2E erweitern:
> kompletter Bon-Flow inkl. Storno (CANCELLATION) und Timeout-Recovery (GET /tx/{id} vor
> Retry — CLAUDE.md TSE-API-Regeln).

**DoD:** Nightly läuft; ein Sandbox-Bon inkl. Storno nachweisbar signiert.

## [ ] S15 — **Fable-Audit #3: TSE/Fiskaly** — ~1 Session Audit + 1 Session Fixes
**Prompt:**
> Führe Audit #3 aus ROADMAP.md durch: Deep-Review ausschließlich über den TSE-Pfad —
> `backend/src/services/fiskaly.ts`, Offline-Queue (`offlineQueueController`, Drain-Cron aus
> S07), Nachsignierungs-Pfad (`receipts.tse_*`-Updates), `tse_outages`-Lebenszyklus,
> payOrder/splitBill/cancelReceipt-TSE-Aufrufe inkl. der S13-Änderungen. Fokus: Idempotenz
> (Doppel-Signatur unmöglich?), Crash-Recovery zwischen TSE-Erfolg und DB-Commit,
> KassenSichV-Meldepflichten (>48h), Beträge/Feldnamen gegen die Fiskaly-Doku. Arbeite wie
> beim Finanz-Integritäts-Audit #2: Nicht-Happy-Paths, Races, Retry-Semantik. Ergebnis:
> Findings mit Schwere + Fix + abgeleiteter Regressionstest. Eintragen in OFFEN.md.

**DoD:** Alle kritischen Findings gefixt + je ein Regressionstest; Audit-Ergebnis in OFFEN.md §1 dokumentiert.

## [ ] S16 — Fiskaly Live + ELSTER (N2 + N3, User + Claude gemeinsam)
- [ ] Fiskaly-Live: TSS für Shishabar anlegen, TSE-Client je iPad (Claude: Onboarding-Pfade prüfen)
- [ ] ELSTER-Kassenanmeldung (manuell, einmalig — Pflicht seit 2025)
- [ ] 1–2 Wochen Pilotbetrieb **mit** TSE; OfflineBanner/pendingCount im Alltag beobachten

## [ ] S17 — DSFinV-K-Gate (N9) — ~0,5 d Vorbereitung + Steuerberater-Termin
**Prompt:**
> Setze Paket S17 aus ROADMAP.md um: DSFinV-K-Export aus den echten Pilot-Daten ziehen
> (`GET /export/dsfinvk`), gegen die amtliche Prüfsoftware (DFKA-Tool / Amadeus Verify —
> aktuelle Optionen recherchieren) laufen lassen, Abweichungen fixen. Begleitdokument für
> den Steuerberater-Termin erstellen: receipt_sequences-Konzept, Storno-Gegenbuchung,
> Offline-TSE-Handling, Z-Bericht-Ablage — je mit Verweis auf Code/Tests.

**DoD:** Prüfsoftware ohne Fehler; schriftliches OK des Steuerberaters liegt vor. **Das ist das Finanzamt-Gate.**

---

# Meilenstein 3 — Go-live

**Gate M3:** Launch-Checkliste komplett · Audit-#4-Findings behoben · ein echter Bon auf Prod-Infrastruktur (Test-Tenant).

**Vorlauf sofort anstoßen (User, Wochen!):** N8 Rechtliches — AGB/Haftung (Anwalt), AVV-Vorlage,
**Verfahrensdokumentation** (GoBD-Pflicht; Claude kann den technischen Teil aus CLAUDE.md +
docs/ generieren), Datenhaltung nach Kündigung.

## [ ] S18 — T6: `any`-Elimination, Geld-Pfade zuerst — ~1–2 d
**Prompt:**
> Setze Paket S18 aus ROADMAP.md um (OFFEN.md T6, Plan steht dort): `src/db/types.ts` mit
> Row-Interfaces für die Geld-Tabellen (OrderRow, ReceiptRow, PaymentRow, SessionRow, …),
> `db.execute<XRow[]>` in payments/splitBill/cancellations/sessions umstellen,
> `ResultSetHeader` für INSERT/UPDATE, `catch (err: unknown)` + Narrowing. ESLint
> `@typescript-eslint/no-explicit-any: error` als Ratchet nur für die umgestellten Dateien
> (Override-Liste), Rest folgt später. Suiten müssen unverändert grün bleiben (mysql2-Generics
> sind Casts — Verhalten darf sich nicht ändern).

**DoD:** Geld-Controller any-frei + ESLint-Ratchet aktiv; Suiten grün.

## [ ] S19 — **Fable-Audit #4: Security/Auth/Stripe** — ~1 Session Audit + Fixes
**Prompt:**
> Führe Audit #4 aus ROADMAP.md durch: Security-Review vor öffentlichem Go-live —
> Auth-Flows (Login/PIN/Refresh/16h-Limit/Passwort-Reset aus S08), Device-Registrierung,
> Rate-Limits (per-IP-Schwächen, S2-Kontext), Stripe-Webhook (Signatur, Idempotenz, Replay),
> CORS/Helmet/Header, Fehlermeldungen auf Info-Leaks, Onboarding (Tenant-Anlage). OWASP-ASVS
> als Checkliste. Findings mit Schwere + Fix + Regressionstest; Eintrag in OFFEN.md §1.

**DoD:** Kritische/hohe Findings gefixt + getestet; Rest priorisiert in OFFEN.md.

## [ ] S20 — Prod-Infrastruktur (N5 + N6 + S6) — ~1–2 d
**Prompt:**
> Setze Paket S20 aus ROADMAP.md um: Hetzner-Setup als dokumentierte Schritte + Scripts —
> Nginx + SSL, PM2 (single instance — Cluster erst nach OFFEN.md S2), Deploy via GitHub
> Actions (CI aus S01 als Gate), MariaDB-Prod: User exakt nach setup-db.ts (app_user OHNE
> DELETE!), **Timezone-Tabellen laden** (`mariadb-tzinfo-to-sql`, sonst liefern alle Berichte
> 0 — CLAUDE.md Betriebshinweis), Pool-Sizing + `innodb_lock_wait_timeout` begründet setzen
> (Session-Locks serialisieren Zahlungen pro Gerät, OFFEN.md S6). Backup aus S11 auf Prod
> aktivieren. Smoke-Test-Script: Health, Login, ein Bon mit Test-Tenant.

**DoD:** Prod erreichbar über HTTPS; Smoke-Test grün; Restore aus Prod-Backup einmal getestet.

## [ ] S21 — Stripe Live + Launch (N4) — ~0,5 d
**Prompt:**
> Setze Paket S21 aus ROADMAP.md um: Stripe-Live-Keys, Webhook-Endpoint im Dashboard,
> Preis-IDs für die 3 Pläne, Webhook-Signatur auf Prod verifiziert (Stripe-CLI-Testevent).
> Launch-Checkliste als docs/launch-checkliste.md generieren und mit mir durchgehen:
> alle M0–M3-Gates, offene OFFEN.md-Punkte mit Prio „Vor Go-live" == leer, Sentry-Alerts
> konfiguriert, Support-Weg für den Wirt definiert.

**DoD:** Erste echte Subscription buchbar (Testlauf mit echtem Abbruch/Refund); Checkliste vollständig abgehakt.

---

# Meilenstein 4 — Nach Go-live (Backlog, bei Bedarf zu Paketen schnüren)

- [ ] S2: Redis-Rate-Limit-Store + per-Tenant-Key (vor Multi-Instanz/PM2-Cluster)
- [ ] S3/S4: Perf (Subscription-Claim im JWT; A5 Report-Queries index-fähig)
- [ ] §6 impeccable-Pass komplett (Rest der UX-Liste in OFFEN.md)
- [ ] T6 Teil 2: `any`-Ratchet auf restliche Dateien ausweiten
- [ ] S5: Docker Compose (Onboarding zweiter Entwickler)
- [ ] Phase 3+: Trinkgeld (erst nach Steuerberater!), SyncManager-Vollausbau, Außer-Haus (Phase 4),
      DATEV/Bondrucker/Multi-iPad (Phase 5) — Differenzierung siehe OFFEN.md §9

---

## Pflege dieser Datei

Nach jeder Session: Paket abhaken, Datum dahinter notieren. Verschiebt sich die Reihenfolge
(z.B. Pilot-Feedback), hier umsortieren **und** kurz begründen — die Reihenfolge ist Teil des
Plans. `OFFEN.md` bleibt die inhaltliche Quelle; diese Datei ist die Abarbeitungsreihenfolge.

# Testkonzept — cashbox Kassensystem

Stand: 2026-07-19. Methodik: Anforderungen (REQ) → Use Cases (UC) → Testfälle (TC) mit Traceability.
Pflege: Neue Anforderungen/Regeln aus CLAUDE.md hier als REQ eintragen, jedem REQ mindestens einen TC zuordnen.
Quellen der Anforderungen: `CLAUDE.md` (Kritische Regeln), `implementierungsplan.md`, GoBD / KassenSichV / § 14 UStG.

**TC-Namensschema:** `TC-U-*` Unit (DB-frei, `npm test`) · `TC-I-*` Integration (Test-DB, `npm run test:integration`) · `TC-E2E-*` Durchstich · `TC-C-*` Nebenläufigkeit · `TC-IOS-*` XCTest · `TC-CI-*` Pipeline-Nachweis (GitHub Actions).

---

## 1. Anforderungskatalog

### Geld (REQ-GELD)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-GELD-001 | Alle Geldbeträge sind Integer in Cent — nie Float/Decimal, auf allen Pfaden (DB, API, iOS) | CLAUDE.md |
| REQ-GELD-002 | Positionsbetrag = `(product_price_cents + Σ modifier_delta_cents) × quantity − discount_cents` | CLAUDE.md |
| REQ-GELD-003 | MwSt aus Brutto: `net = round(gross / (1 + rate))`, `tax = gross − net` — Brutto == Netto + Steuer Cent-genau, je Satz (7 %/19 %) getrennt | implementierungsplan |
| REQ-GELD-004 | Split-Partitionsinvariante: jedes Order-Item in genau einem Split; je Split Zahlungssumme == Item-Summe | splitBillController |
| REQ-GELD-005 | payments-Summe == Order-Total bei jeder Zahlung (Einzel wie Gemischt), sonst 422 | paymentsController |
| REQ-GELD-006 | iOS rechnet MwSt mit identischer Formel wie das Backend (Formelparität) | PaymentView |

### GoBD / KassenSichV (REQ-GOBD)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-GOBD-001 | Kein DELETE/UPDATE auf Finanzdaten (orders, order_items, receipts, payments, cancellations, audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals) — DB-User-Grants erzwingen das | CLAUDE.md |
| REQ-GOBD-002 | Bon-Nummern lückenlos und fortlaufend aus `receipt_sequences` via `SELECT … FOR UPDATE` | CLAUDE.md |
| REQ-GOBD-003 | Bon-Nummer vergeben + TX-Fehler → Receipt mit `status='voided'` (dokumentierte Lücke), niemals skippen | CLAUDE.md |
| REQ-GOBD-004 | Storno = Gegenbuchung: neuer Bon mit negierten Beträgen (`vat_*`, `total_gross_cents`) + negative payments je Original-Zahlungsmittel; Items im JSON bleiben positiver Original-Snapshot; alle SUM()-Aggregationen netten aus | CLAUDE.md |
| REQ-GOBD-005 | `raw_receipt_json` wird genau einmal geschrieben (bei `status='active'`), danach kein UPDATE | CLAUDE.md |
| REQ-GOBD-006 | Session-Lock-Invariante: payOrder/splitBill/cancelReceipt sperren die Session-Zeile (FOR UPDATE), 409 wenn nicht `open`; closeSession aggregiert+schließt unter demselben Lock — kein Bon kann in eine geschlossene Session buchen | CLAUDE.md (Audit #2) |
| REQ-GOBD-007 | Doppel-Storno unmöglich: UNIQUE(original_receipt_id) + FOR-UPDATE-Check | CLAUDE.md (Audit #2) |
| REQ-GOBD-008 | Preisänderung nur via `POST /products/:id/price`: erst `product_price_history`-INSERT, dann UPDATE; `price_cents` via PATCH verboten | CLAUDE.md |
| REQ-GOBD-009 | Item-Entfernung = INSERT in `order_item_removals` (wer/wann/warum), Original-Zeile bleibt | CLAUDE.md |
| REQ-GOBD-010 | Bon-Pflichtfelder (KassenSichV § 6, § 14 UStG): device_id/device_name-Snapshot, Tenant-Snapshot, MwSt-Aufschlüsselung, TSE-Felder bzw. tse_pending | receipts-Service |
| REQ-GOBD-011 | Z-Bericht wird beim Schließen unveränderlich in `z_reports` persistiert; expected_cash = opening + bar-Zahlungen ± Movements; Storno-Bons netten | sessionsController |

### Tenant-Isolation (REQ-TENANT)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-TENANT-001 | Jede Query enthält `WHERE tenant_id = ?`; Tabellen ohne tenant_id (z.B. payments) nur über JOIN auf eine tenant-geprüfte Tabelle | CLAUDE.md |
| REQ-TENANT-002 | tenant_id ausschließlich aus JWT (tenantMiddleware), nie aus Body/URL | CLAUDE.md |
| REQ-TENANT-003 | Fremde Ressourcen → 404 (nicht 403, kein Existenz-Leak) | CLAUDE.md |

### TSE / Fiskaly (REQ-TSE)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-TSE-001 | Jede TSE-Operation hat idempotency_key (UUID) in offline_queue | CLAUDE.md |
| REQ-TSE-002 | Beträge an Fiskaly als String mit 2 Dezimalstellen ("30.50"), negativ bei Storno | CLAUDE.md |
| REQ-TSE-003 | `amounts_per_vat_rate` (Singular!) mit required `amount` (Brutto) + `excl_vat_amounts`; 0-Sätze weggelassen | CLAUDE.md |
| REQ-TSE-004 | Vollständiges Schema bei jedem PUT, auch FINISHED | CLAUDE.md |
| REQ-TSE-005 | Fiskaly 5xx/Timeout → Verkauf läuft weiter: tse_pending=TRUE, offline_queue-Eintrag, tse_outages öffnet/schließt | fiskaly.ts |

### UX / iOS (REQ-UX)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-UX-001 | Keine Sackgasse nach Zahlungsversuch: 409/Timeout → Order-Status nachladen, wenn bezahlt Bon zeigen (A4) | OFFEN.md A4 |
| REQ-UX-002 | Deutsche Betragseingabe/-anzeige: parseCents akzeptiert "12,50"/"12.50"/„€", euroString formatiert `1.234,56 €` | DesignSystem |
| REQ-UX-003 | Gemischt-Zahlung: bar==total → nur cash; bar<total → Rest als card, Summe == total; bar>total wird nicht abgeschickt | PaymentView |
| REQ-UX-004 | iOS decodiert alle Backend-Responses mit der Produktions-Decoder-Konfiguration (snake_case) verlustfrei | APIClient |

### Prozess / CI (REQ-CI)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-CI-001 | Keine Änderung erreicht `main`, ohne dass Typecheck + Unit/Compliance + Integrationstests grün durchlaufen — erzwungen als Required Status Check, nicht als Konvention | ROADMAP S01 |
| REQ-CI-002 | CI läuft gegen eine echte MariaDB mit geladenen Timezone-Tabellen; fehlen sie, bricht der Lauf ab statt Berichte still mit 0 zu testen | CLAUDE.md Betriebshinweis |
| REQ-CI-003 | Die iOS-XCTest-Suite ist Teil desselben Gates; das Scheme ist geteilt und die Simulator-Destination wird zur Laufzeit ermittelt (Runner-Images variieren) | ROADMAP S02 |

### Betrieb / Monitoring (REQ-OPS)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-OPS-001 | Der Prozess fährt auf SIGTERM/SIGINT kontrolliert herunter: laufende Requests zu Ende (Drain), dann Monitoring flushen, dann DB-Pools schließen. Ein Deploy darf keine angefangene Bon-Transaktion abreißen. Hängt der Drain, greift eine Notbremse statt eines späteren SIGKILL | ROADMAP S03 / OFFEN.md B6 |
| REQ-OPS-002 | 5xx werden ans Error-Monitoring gemeldet (Sentry), 4xx nicht; Kontext ist tenant_id (aus JWT), URL und Methode — keine Bodies, Header oder Beträge (DSGVO/AVV) | ROADMAP S03 / OFFEN.md S1 |
| REQ-OPS-003 | `unhandledRejection`/`uncaughtException` beenden den Prozess kontrolliert statt Node hart crashen zu lassen — vorher loggen und an Sentry melden | ROADMAP S03 / OFFEN.md B6 |
| REQ-OPS-004 | In Production erreicht kein Stack Trace / keine interne Fehlermeldung den Client | app.ts |
| REQ-OPS-005 | Ein Testlauf meldet nichts ans Error-Monitoring — Testfehler dürfen das Produktions-Dashboard nicht verfälschen, auf dem die Alert-Regeln sitzen | OFFEN.md T10 |

### E-Mail (REQ-MAIL)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-MAIL-001 | Beträge in E-Mails sind exakt so formatiert wie im Frontend (`euroString()`: Tausenderpunkt, Dezimalkomma, zwei Nachkommastellen) — der Wirt sieht in der Mail dieselbe Zahl wie auf dem iPad | ROADMAP S05 / OFFEN.md §5 |
| REQ-MAIL-002 | Datums- und Zeitangaben in E-Mails stehen in Europe/Berlin, nie in UTC (dieselbe Falle wie bei den Berichten, T9) | ROADMAP S05 |
| REQ-MAIL-003 | Fremdtext (Betriebsname, Gerätename, Fehlertext) wird vor dem Einbetten HTML-escaped — keine Injection über Mail-Inhalte | ROADMAP S05 |
| REQ-MAIL-004 | Jedes Template liefert Betreff, HTML **und** Plaintext; HTML ist 600 px Single Column mit Dark-Mode-Regeln (Spam-Bewertung + Clients ohne HTML) | OFFEN.md §5 |
| REQ-MAIL-005 | Ein Fehlversand geht nicht verloren: die Mail bleibt in der Queue und wird mit wachsendem Abstand erneut versucht, bis `max_attempts` erreicht ist (dann `failed` + Sentry) | OFFEN.md §5 |
| REQ-MAIL-006 | Doppelter Lauf desselben Anlasses erzeugt keine zweite Mail (Idempotenz-Schlüssel als UNIQUE) — Voraussetzung für die Cron-Jobs in S07 | ROADMAP S07 |
| REQ-MAIL-007 | Jeder tatsächliche Versand wird in `email_log` nachgewiesen (INSERT-only via `audit_insert_user`, mit `provider_message_id`) — bei KassenSichV-Meldemails muss der Versand belegbar sein | OFFEN.md §5 |
| REQ-MAIL-008 | Nach erfolgreichem Versand werden Betreff und Körper in der Queue genullt (DSGVO-Datenminimierung); der Nachweis bleibt in `email_log` | ROADMAP S05 |

---

## 2. Use Cases (Kassenalltag)

| ID | Use Case | Berührte REQs |
|----|----------|---------------|
| UC-01 | Schicht öffnen (Eröffnungsbestand zählen) | GOBD-006, GOBD-011 |
| UC-02 | Bestellung aufnehmen (Tisch, Items, Modifier, Rabatt) | GELD-001/002, GOBD-009, TENANT-* |
| UC-03 | Bar bezahlen (mit Rückgeld) | GELD-003/005, GOBD-002/003/010 |
| UC-04 | Karte bezahlen (ehrlicher 2-Schritt, Phase 1 ohne Terminal) | GELD-003/005, GOBD-* |
| UC-05 | Gemischt bezahlen (bar + Karte) | GELD-005, UX-003 |
| UC-06 | Rechnung splitten (getrennte Bons je Gast) | GELD-004, GOBD-002 |
| UC-07 | Bon stornieren (gleicher Tag) | GOBD-004/007 |
| UC-08 | Einlage / Entnahme (Movements) | GOBD-011 |
| UC-09 | Schicht schließen, Kasse zählen, Z-Bericht | GOBD-006/011 |
| UC-10 | WLAN-Aussetzer beim Bezahlen → Retry | UX-001, GOBD-006 |
| UC-11 | Doppel-Tap / paralleler Zugriff (2 Requests gleichzeitig) | GOBD-002/006/007 |
| UC-12 | Folgetag-Storno (Storno in Session B für Bon aus Session A) | GOBD-004/011 |
| UC-13 | Betriebsprüfung: DSFinV-K-Export | GOBD-001…011 |
| UC-14 | Preis ändern (GoBD-Historie) | GOBD-008 |
| UC-15 | Offline-Betrieb / TSE-Nachsignierung | TSE-001/005 |
| UC-OPS-01 | Deploy/Neustart während des Betriebs (SIGTERM, laufende Zahlung) | OPS-001/003 |
| UC-OPS-02 | Serverfehler beim Kunden — wird sichtbar, ohne dass jemand Logs liest | OPS-002/004 |
| UC-MAIL-01 | Trial läuft aus — der Wirt wird rechtzeitig gewarnt (Tag 10 + 13) | MAIL-001…004/006/008 |
| UC-MAIL-02 | KassenSichV-Pflichtmail (TSE-Ausfall > 48 h) — Versand muss belegbar sein | MAIL-003/004/007 |
| UC-MAIL-03 | Mail-Anbieter ist kurz nicht erreichbar — nichts geht verloren | MAIL-005 |

---

## 3. Traceability-Matrix

Bestandsdateien: `backend/src/__tests__/integration/*` (20 Dateien), `compliance/receipt-fields.test.ts`, `unit/vatCalculation.test.ts`. Neue Dateien aus der Test-Offensive sind **fett**.

| REQ | UC | Testfälle (Datei) |
|-----|----|-------------------|
| GELD-001 | alle | implizit alle Suiten (Fixtures nur Cent-Integer); TC-U in **vatCalculation**, **fiskalyPayload** |
| GELD-002 | UC-02 | TC-I orders.test.ts (Item + Modifier + Rabatt); TC-I modifierGroups.test.ts |
| GELD-003 | UC-03/04 | TC-U unit/vatCalculation.test.ts; TC-I payments.test.ts, mixed-payments.test.ts |
| GELD-004 | UC-06 | **TC-U unit/splitPartition.test.ts**; TC-I split-bill.test.ts |
| GELD-005 | UC-03/05 | TC-I payments.test.ts (422 bei Summenabweichung), mixed-payments.test.ts |
| GELD-006 | UC-03 | **TC-IOS VatBreakdownTests** (Paritätsfälle aus vatCalculation.test.ts) |
| GOBD-001 | UC-13 | DB-Grants: scripts/setup-db.ts (Prod-Absicherung, A6 offen); Storno-statt-DELETE: cancellations.test.ts |
| GOBD-002 | UC-03/06 | **TC-U unit/sequences.test.ts**; **TC-E2E e2e-tagesablauf** (Lückenlosigkeit 1…N); **TC-C concurrency** |
| GOBD-003 | UC-03 | TC-I payments.test.ts (voided bei TX-Fehler) |
| GOBD-004 | UC-07/12 | **TC-U unit/cancellationNegation.test.ts**; TC-I cancellations.test.ts (inkl. Folgetag-Storno); **TC-E2E** |
| GOBD-005 | UC-03 | TC-I receipts.test.ts; compliance/receipt-fields.test.ts |
| GOBD-006 | UC-09/10/11 | TC-I sessions.test.ts (409 auf geschlossene Session); **TC-C concurrency (pay vs. close)** |
| GOBD-007 | UC-07/11 | TC-I cancellations.test.ts (UNIQUE-Backstop); **TC-C concurrency (Doppel-Storno parallel)** |
| GOBD-008 | UC-14 | TC-I products.test.ts (price-Route + PATCH-Verbot) |
| GOBD-009 | UC-02 | TC-I orders.test.ts (removeItem → order_item_removals) |
| GOBD-010 | UC-03/13 | compliance/receipt-fields.test.ts |
| GOBD-011 | UC-08/09/12 | **TC-U unit/zReportAggregation.test.ts**; TC-I sessions.test.ts; **TC-E2E** (expected_cash, Differenz 0) |
| TENANT-001…003 | alle | je ein Tenant-Isolation-`it()` in allen 20 Integrationsdateien (Konvention: Pflicht bei jeder neuen Route) |
| TSE-001 | UC-15 | TC-I offline-queue.test.ts |
| TSE-002/003/004 | UC-15 | **TC-U unit/fiskalyPayload.test.ts**; external/fiskaly.test.ts (Sandbox, nightly) |
| TSE-005 | UC-15 | TC-I payments.test.ts (tse_pending-Pfad); offline-queue.test.ts |
| UX-001 | UC-10 | TC-I orders.test.ts (receipt-Block in GET /orders/:id); **TC-IOS ModelDecodingTests** (receipt-Fixture) |
| UX-002 | UC-03 | **TC-IOS ParseCentsTests, EuroStringTests** |
| UX-003 | UC-05 | **TC-IOS PaymentLogicTests** |
| UX-004 | alle | **TC-IOS ModelDecodingTests** (Fixtures je Response-Typ) |
| CI-001 | alle | **TC-CI-001**: PR mit absichtlich rotem Unit-Test → Check `backend` rot, PR nicht mergebar (Nachweis-Protokoll in `docs/ci.md`) |
| CI-002 | UC-09/13 | **TC-CI-002**: Guard-Step „Timezone-Tabellen verifizieren" in `.github/workflows/ci.yml` — `CONVERT_TZ` NULL ⇒ Job-Abbruch |
| CI-003 | alle iOS-UCs | **TC-CI-003**: PR mit absichtlich rotem XCTest → Check `iOS (xcodebuild test)` rot (Nachweis-Protokoll in `docs/ci.md`) |
| OPS-001 | UC-OPS-01 | **TC-U unit/shutdown.test.ts** (Reihenfolge Drain→Flush→Pools, Idempotenz bei zweitem Signal, Exit-Code bei Pool-Fehler, Notbremse bei hängendem Drain); **TC-M Manuell**: `kill -TERM` gegen laufenden Server, Log zeigt Drain (Protokoll in `docs/betrieb.md`) |
| OPS-002 | UC-OPS-02 | **TC-I integration/errorHandler.test.ts** (5xx → captureException mit tenant/url/method; 4xx → nicht gemeldet); **TC-M Manuell**: Envelope-Nachweis gegen lokalen Ingest (`docs/betrieb.md`) |
| OPS-003 | UC-OPS-01 | abgedeckt über OPS-001 (derselbe Shutdown-Pfad, Exit-Code 1); Verdrahtung der Handler: `src/index.ts` |
| OPS-004 | UC-OPS-02 | **TC-I integration/errorHandler.test.ts** (Production: `error` == „Interner Serverfehler.", kein Leak) |
| OPS-005 | UC-OPS-02 | **TC-U unit/sentryConfig.test.ts** (unter NODE_ENV=test ist `sentryEnabled === false` und kein DSN in der Umgebung) |
| MAIL-001 | UC-MAIL-01 | **TC-U unit/emailTemplates.test.ts** (euroString: Tausenderpunkt, 2 Nachkommastellen, negativ, groß) |
| MAIL-002 | UC-MAIL-01/02 | **TC-U unit/emailTemplates.test.ts** (formatDate/formatDateTime: Sommer-/Winterzeit, 22:30 UTC → Folgetag) |
| MAIL-003 | UC-MAIL-01/02 | **TC-U unit/emailTemplates.test.ts** (esc, Label-Spalte, Überschrift, Betriebsname im Template) |
| MAIL-004 | UC-MAIL-01/02 | **TC-U unit/emailTemplates.test.ts** (Registry-Schleife: Betreff + Plaintext + 600px + Dark-Mode je Template) |
| MAIL-005 | UC-MAIL-03 | **TC-U unit/emailTemplates.test.ts** (backoffMinutes monoton + Deckel); **TC-I integration/email-queue.test.ts** (Retry eingeplant, Wiederaufnahme, `failed` nach max_attempts, Stuck-Claim-Reset) |
| MAIL-006 | UC-MAIL-01 | **TC-I integration/email-queue.test.ts** (zweites Enqueue → false, nur eine Zeile; day10/day13 getrennt) |
| MAIL-007 | UC-MAIL-02 | **TC-I integration/email-queue.test.ts** (email_log-Zeile mit provider_message_id; kein Log bei Fehlversand; INSERT via auditDb) |
| MAIL-008 | UC-MAIL-01 | **TC-I integration/email-queue.test.ts** (subject/body_html/body_text nach Erfolg NULL) |

---

## 4. Gap-Analyse (Begründung der Test-Offensive)

Stand vor der Offensive (2026-07-19):

1. **Unit-Ebene fast leer (T1):** nur `vatCalculation.test.ts`. Split-Validierung, Storno-Negation, Z-Bericht-Aggregation, Sequenzen und Fiskaly-Payload waren ausschließlich über Integrationstests indirekt abgedeckt — Kantenfälle (1-Cent-Abweichungen, 0-Beträge, Rundung) fehlten. → `unit/splitPartition`, `unit/cancellationNegation`, `unit/zReportAggregation`, `unit/sequences`, `unit/fiskalyPayload`.
2. **Kein Durchstich (T3):** 20 Integrationsdateien testen je eine Domäne isoliert; niemand prüfte den ganzen Tag inkl. sessionübergreifender Invarianten (expected_cash über alle Zahlarten, Bon-Nummern-Lückenlosigkeit über Einzel-/Split-/Storno-Bons hinweg). → `integration/e2e-tagesablauf`.
3. **Locks ohne Regressionsschutz (T4):** Die Audit-#2-Fixes (Session-Lock, Doppel-Storno-UNIQUE) wurden per Direkt-INSERT simuliert, nie mit echten parallelen Requests. → `integration/concurrency`.
4. **iOS ungetestet (T2):** kein XCTest-Target; Geld-Funktionen (parseCents, euroString, buildPayments, VatBreakdown) und Response-Decoding liefen nur manuell. Formelparität iOS↔Backend war unbewiesen. → Target `zettel-frontendTests` + 5 Testdateien.
5. **A4/UX-001:** Zahlungs-Retry nach 409/Timeout endete in Sackgasse (behoben 2026-07-19, Block 0).

Nicht Teil dieser Offensive (bewusst): Fiskaly-Sandbox-E2E (Phase 2, external/nightly), Last-/Performance-Tests (nach Pilot, OFFEN.md S6), UI-/Snapshot-Tests iOS (kein Ersatz für die manuelle AX1-Screenshotmatrix, OFFEN.md §6).

---

## 5. Testdaten-Regeln

1. **GoBD auch im Test:** DELETE auf Finanztabellen nur in der Test-DB und nur via `testHelpers.cleanTestDB` (FK-sichere Reihenfolge). Kein Test räumt selbst per DELETE auf.
2. **Geld:** Fixtures ausschließlich Cent-Integer; bevorzugt krumme Beträge (1999, 350, 5 statt 1000), damit Rundungsfehler auffallen.
3. **MwSt:** Fixtures mit gemischten Sätzen (7 % + 19 % in einer Order), damit Aggregations-/Aufschlüsselungsfehler auffallen.
4. **Tenant-Isolation:** Jede neue Integrationsdatei enthält mindestens einen Fremd-Tenant-`it()` (Erwartung: 404).
5. **Nebenläufigkeit:** Race-Tests asserten legale Ergebnismengen (z.B. `{201, 409}`), nie Reihenfolgen; jede Race wird mehrfach wiederholt.
6. **iOS-Fixtures:** JSON-Fixtures sind wörtliche Backend-Responses (snake_case), decodiert mit der Produktions-Decoder-Konfiguration — nie handgebaute Codable-freundliche Varianten.

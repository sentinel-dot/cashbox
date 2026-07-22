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
| REQ-GOBD-012 | `audit_insert_user` hat INSERT **nur** auf den sechs append-only-Tabellen (audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals, email_log) — kein datenbankweites INSERT, keine anderen Rechte | OFFEN.md A6 (S09) |
| REQ-GOBD-013 | Scheitert der `order_item_modifiers`-INSERT nach dem Commit der Position, wird die Position unter dem Order-Lock über `order_item_removals` kompensiert (kein DELETE) und 500 geantwortet — Retry erzeugt kein Duplikat; ist die Order nicht mehr offen, wird nicht entfernt, sondern gemeldet | OFFEN.md A3 (S09) |

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
| REQ-MAIL-009 | Die sechs Template-Gruppen decken Trial-Warnung, TSE-Ausfall >48 h, Passwort-Reset, Z-Bericht, Subscription-Events und Session >24 h ab; jede enthält die anlassbezogenen Pflichtinformationen in HTML und Plaintext | ROADMAP S06 / OFFEN.md §5 |
| REQ-MAIL-010 | Öffentliche Anlassfunktionen verwenden ausschließlich stabile technische IDs im Idempotenzschlüssel; Reset-Token, Empfänger und Betriebsnamen dürfen dort nicht auftauchen | ROADMAP S06 |
| REQ-MAIL-011 | Produktionsversand wird erst mit einer eigenen, in Resend SPF-/DKIM-verifizierten Domain und eingerichtetem DMARC aktiviert; ohne API-Key bleibt der Dienst im sicheren Dry-Run | ROADMAP S05/S06 |

### Hintergrund-Jobs / Cron (REQ-CRON)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-CRON-001 | Die Trial-Warnung geht an Tag 10 und Tag 13 an den Owner — je Marker genau einmal, auch bei mehrfachem Lauf. Warnung und Sperre benutzen dieselben Fristen (`services/subscription.ts`); vor Tag 10, nach Ablauf und bei bezahltem Abo wird nicht gewarnt | ROADMAP S07 / OFFEN.md B2 |
| REQ-CRON-002 | Läuft die Kulanzfrist nach `past_due` ab, wird das einmalig sichtbar: Mail an den Owner, `audit_log`-Eintrag, Sentry-Alert. Der Job ändert `subscription_status` **nicht** — gesperrt wird in der `subscriptionMiddleware`, Stripe bleibt alleinige Quelle des Abo-Status | ROADMAP S07 (Entscheidung 2026-07-22) |
| REQ-CRON-003 | Kassensitzungen, die länger als 24 h offen sind, lösen genau eine Owner-Mail je Sitzung aus (GoBD: täglicher Abschluss); geschlossene und junge Sitzungen bleiben unberührt | OFFEN.md B2 / CLAUDE.md Kassensitzungspflicht |
| REQ-CRON-004 | TSE-Ausfälle > 48 h werden gemeldet und mit `tse_outages.notified_at` als Nachweis markiert; beendete oder bereits gemeldete Ausfälle lösen nichts mehr aus. Die Mail wird vor dem Setzen des Markers eingereiht — eine Pflichtmeldung darf eher doppelt als gar nicht rausgehen | KassenSichV / OFFEN.md B2 |
| REQ-CRON-005 | Die Nachsignierung offener Offline-Bons läuft serverseitig und tenant-übergreifend, ohne dass ein iPad synchronisiert — über denselben Code und dieselben atomaren Claims wie `POST /sync/offline-queue`, sodass Client und Cron parallel laufen dürfen | OFFEN.md B2 / KassenSichV |
| REQ-CRON-006 | Jeder endgültig gescheiterte Offline-Queue-Eintrag wird genau einmal gemeldet (`offline_queue.alerted_at`) — kein stündlich wiederholter Alarm für denselben Vorfall | OFFEN.md B2 |
| REQ-CRON-007 | Geschlossene Sitzungen ohne `z_reports`-Zeile werden gefunden, aus den unveränderten Buchungsdaten nachgetragen und gemeldet. Der Nachtrag ist im Snapshot als solcher markiert, rechnet identisch zum regulären Abschluss und kann nicht doppelt entstehen (UNIQUE `z_reports.session_id`, V012) | OFFEN.md §1 A9 |
| REQ-CRON-008 | Die Mail-Queue wird periodisch geleert — ohne diesen Job bleibt jede eingereihte Mail liegen (S05/S06 hatten keinen Auslöser) | ROADMAP S05/S07 |
| REQ-CRON-009 | Jeder Job ist einzeln auslösbar (`npm run job -- <name>`), hat einen gültigen Zeitplan in Europe/Berlin, und ein geworfener Job beendet weder den Prozess noch verhindert er die übrigen Jobs | ROADMAP S07 DoD |

### Sortiment (REQ-SORT)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-SORT-001 | `GET /products` liefert per Default nur aktive Produkte (Kasse); `?include_inactive=1` liefert zusätzlich inaktive für die Management-Ansicht — deaktivierte Produkte sind reaktivierbar | OFFEN.md UX-S1 / ROADMAP S17A |
| REQ-SORT-002 | Query-Params der Produktliste werden strikt validiert (safeParse, unbekannte Keys → 400) — kein stilles Ignorieren | CLAUDE.md Validierung |
| REQ-SORT-003 | Produkte haben eine persistente Kassen-Reihenfolge (`products.sort_order`); `POST /products` persistiert sie (Default: Ende der Kategorie, MAX+10) | OFFEN.md UX-S1 |
| REQ-SORT-004 | Die Produktliste ist deterministisch sortiert: Kategorie-sort_order → Kategorie-Name → Produkt-sort_order → Produkt-Name → ID; Produkte ohne Kategorie zuletzt. iOS spiegelt exakt dieselbe Ordnung (`assortmentSorted`) | ROADMAP S17A DoD |
| REQ-SORT-005 | Reorder-Endpoints (`PATCH /products/reorder`, `PATCH /products/categories/reorder`) sind tenant-verifiziert (fremde ID → 404, nichts geändert), owner/manager-only, transaktional und idempotent | CLAUDE.md Tenant-Isolation |
| REQ-SORT-006 | Der Kategorie-Löschdialog in iOS beschreibt das echte Backend-Verhalten (Soft-Delete; 409 bei aktiven Produkten) — keine falschen Versprechen („Produkte werden nicht zugeordnet") | OFFEN.md UX-S1 |

### Starter-Sortimente (REQ-PRESET)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-PRESET-001 | Die V1-Presetdaten entsprechen exakt der Spezifikation: Shisha-Bar 4/21, Café 4/25, Späti 5/27 + 3 Tabakvorlagen, Leer 0/0; IDs/Keys eindeutig, MwSt nur 7/19, `price_cents` immer null | docs/s17-sortiment-starterpakete.md §3–5, §11 |
| REQ-PRESET-002 | Es gibt genau EINEN Produktanlage-Pfad (`createProductWithHistory`): inaktiv anlegen → initiale `product_price_history` via auditDb → Werte verifizieren → aktivieren. Ein aktives Produkt ohne Historie ist unmöglich; das härtet auch `POST /products` | Spec §8.3 |
| REQ-PRESET-003 | Der Import ist auf DB-Ebene idempotent: UNIQUE `(tenant, origin_preset_id, origin_item_key)` + `preset_imports`-Claim je `(tenant, Idempotency-Key)`. Replay liefert das gespeicherte Ergebnis (200), paralleler Doppeltap verarbeitet genau einmal, Retry nach Fehler repariert inaktive Reste statt zu duplizieren | Spec §8.2 |
| REQ-PRESET-004 | Vom Betreiber deaktivierte Import-Produkte werden durch Re-Import NIE still reaktiviert; Namensgleichheit ist nie ein automatischer Merge (skip/create explizit) | Spec §8.2 |
| REQ-PRESET-005 | Serverseitige Re-Validierung gegen die eigene Preset-Definition: unbekannte Keys 400, Standard-/Speisen-Sätze nicht frei änderbar, `recipe_review`/`printed_price_review` nur mit Einzelbestätigung, Tabakvorlagen nur mit konkretem Namen, Bulk-Plan-Limit | Spec §2.3, §5.3, §8.1 |
| REQ-PRESET-006 | Pfand-Gate: die elf `deposit_cents=25`-Zeilen werden server- UND UI-seitig abgewiesen (400 `deposit_gate`), bis ein eigenes auditiertes Pfand-Paket existiert; Pfand nie in `price_cents` | Spec §5.4 / OFFEN.md UX-S5 |
| REQ-PRESET-007 | `visual_key` ist eine 39er-Whitelist (semantische Keys, nie SF-Symbol-Namen in der DB); `null` = gleichwertige Textkachel; unbekannte Zukunftswerte rendern defensiv als `generic` und brechen weder Decoding noch Verkauf | Spec §6.1–6.2 |
| REQ-PRESET-008 | Die Namensheuristik ist nur Picker-Vorbelegung: Ganze-Wort-Matching (kein „tee" in „Teekanne"), spezifischste Regel zuerst, Kategorie sekundär, kein Treffer ⇒ nil (nie `generic`), manuelle Wahl wird nie überschrieben | Spec §6.4 |
| REQ-PRESET-009 | Wizard-Bestätigungen: Sammelbestätigung deckt ausschließlich Standard-/Speisenzeilen; Risikozeilen brauchen Einzelbestätigung; Import erst wenn alle ausgewählten Zeilen bestätigt und bepreist (> 0) sind | Spec §2.3, §9 |
| REQ-PRESET-010 | Jeder Import wird als `preset.imported` mit vollständigem Snapshot (Preset, Version, `tax_basis_version`, bestätigte Werte) im Audit-Log dokumentiert | Spec §8.3.6 |

### Passwort-Reset (REQ-PWR)

| ID | Anforderung | Quelle |
|----|-------------|--------|
| REQ-PWR-001 | `POST /auth/forgot-password` antwortet **immer** 200 — unbekannte E-Mail, unbekanntes Gerät, deaktivierter Nutzer und Drosselung sind von außen nicht unterscheidbar (kein User-Enumeration-Leak) | ROADMAP S08 / OFFEN.md B3 |
| REQ-PWR-002 | Der Tenant kommt wie beim Login aus dem registrierten Gerät, nie aus dem Request-Body — dieselbe E-Mail in einem anderen Betrieb bleibt unberührt | CLAUDE.md Tenant-Isolation |
| REQ-PWR-003 | Der Klartext-Token existiert ausschließlich in der Mail; in der DB steht nur `SHA2(token,256)`. Er taucht weder in Logfiles (`redactUrl`) noch in `email_queue`-Idempotenzschlüsseln auf | ROADMAP S08 / REQ-MAIL-010 |
| REQ-PWR-004 | Ein Token ist genau einmal und maximal eine Stunde einlösbar. Ein neu angeforderter Link entwertet den vorherigen; abgelaufene, verbrauchte und unbekannte Token ändern kein Passwort | OFFEN.md B3 |
| REQ-PWR-005 | Zwei gleichzeitige Einlösungen desselben Links setzen das Passwort genau einmal (`FOR UPDATE` auf der Token-Zeile) | CLAUDE.md Race-Regeln |
| REQ-PWR-006 | Missbrauchsschutz zweistufig: IP-Rate-Limit auf beiden Routen und höchstens `MAX_REQUESTS_PER_HOUR` Reset-Mails je Nutzer und Stunde (Schutz eines fremden Postfachs trotz „immer 200") | ROADMAP S08 |
| REQ-PWR-007 | Ein erfolgreicher Reset beendet ältere Sitzungen: `/auth/refresh` gibt 401, wenn der `session_start`-Claim vor `users.password_changed_at` liegt. Danach begonnene Sitzungen und Bestandsnutzer ohne Zeitstempel bleiben gültig | ROADMAP S08 (Entscheidung 2026-07-22) |
| REQ-PWR-008 | Die Reset-Seite wird serverseitig gerendert, kommt ohne JavaScript aus, escaped den Token im Formular und wird nicht gecacht (`no-store`, `Referrer-Policy: no-referrer`, `noindex`) | ROADMAP S08 (Entscheidung 2026-07-22) |
| REQ-PWR-009 | Fehleingaben im Formular (zu kurz, Wiederholung abweichend) liefern die Seite mit verständlicher Meldung erneut und verbrauchen den Token nicht | ROADMAP S08 DoD |
| REQ-PWR-010 | Anfrage und Durchführung sind im `audit_log` nachvollziehbar (`user.password_reset_requested`, `user.password_reset`) | GoBD/Sicherheit |

---

## 2. Use Cases (Kassenalltag)

| ID | Use Case | Berührte REQs |
|----|----------|---------------|
| UC-01 | Schicht öffnen (Eröffnungsbestand zählen) | GOBD-006, GOBD-011 |
| UC-02 | Bestellung aufnehmen (Tisch, Items, Modifier, Rabatt) | GELD-001/002, GOBD-009/013, TENANT-* |
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
| UC-13 | Betriebsprüfung: DSFinV-K-Export | GOBD-001…012 |
| UC-18 | Der Audit-DB-Account fällt aus (Grant weg, Pool tot) mitten in einer Bestellung | GOBD-012/013 |
| UC-14 | Preis ändern (GoBD-Historie) | GOBD-008 |
| UC-15 | Offline-Betrieb / TSE-Nachsignierung | TSE-001/005 |
| UC-OPS-01 | Deploy/Neustart während des Betriebs (SIGTERM, laufende Zahlung) | OPS-001/003 |
| UC-OPS-02 | Serverfehler beim Kunden — wird sichtbar, ohne dass jemand Logs liest | OPS-002/004 |
| UC-MAIL-01 | Trial läuft aus — der Wirt wird rechtzeitig gewarnt (Tag 10 + 13) | MAIL-001…004/006/008 |
| UC-MAIL-02 | KassenSichV-Pflichtmail (TSE-Ausfall > 48 h) — Versand muss belegbar sein | MAIL-003/004/007/009…011 |
| UC-MAIL-03 | Mail-Anbieter ist kurz nicht erreichbar — nichts geht verloren | MAIL-005 |
| UC-MAIL-04 | Passwort vergessen — der einmalige Reset-Link ist eine Stunde gültig | MAIL-003/004/009/010 |
| UC-MAIL-05 | Tagesabschluss — Owner erhält opt-in Umsatz, Zahlarten und Kassendifferenz | MAIL-001…004/009 |
| UC-MAIL-06 | Abo-Status ändert sich — past_due, Kündigung und Reaktivierung führen zu einer handlungsfähigen Nachricht | MAIL-003/004/009/010 |
| UC-MAIL-07 | Schicht bleibt länger als 24 Stunden offen — Owner erhält eine GoBD-Warnung | MAIL-002…004/009/010 |
| UC-CRON-01 | Trial läuft aus, während niemand zusieht — Warnungen und Sperre bleiben synchron | CRON-001, MAIL-006 |
| UC-CRON-02 | Zahlung scheitert dauerhaft: Kulanzfrist läuft ab, der Wirt erfährt es (ohne dass die Kasse still den Status umschreibt) | CRON-002 |
| UC-CRON-03 | Schicht wurde abends vergessen zu schließen | CRON-003, GOBD-011 |
| UC-CRON-04 | TSE fällt über zwei Tage aus — Meldepflicht wird belegbar ausgelöst | CRON-004, TSE-005, MAIL-007 |
| UC-CRON-05 | Das iPad kommt nach dem Ausfall nie wieder online — der Server signiert trotzdem nach | CRON-005, TSE-001/005 |
| UC-CRON-06 | Ein Bon lässt sich endgültig nicht signieren — genau ein Alarm, nicht 24 pro Tag | CRON-006 |
| UC-CRON-07 | Z-Bericht fehlt nach dem Schließen (A9) — Nachtrag aus unveränderten Daten, sichtbar markiert | CRON-007, GOBD-011 |
| UC-CRON-08 | Deploy/Neustart löst alle Jobs erneut aus — nichts passiert doppelt | CRON-001…008 |
| UC-CRON-09 | Betrieb löst nach einem Vorfall einen Job von Hand aus | CRON-009 |
| UC-16 | Sortiment pflegen (Produkt deaktivieren → reaktivieren, Reihenfolge ziehen, Kategorie anlegen/löschen) | SORT-001…006, TENANT-* |
| UC-17 | Frischer Tenant richtet Starter-Sortiment ein (< 10 min, 3 Kategorien + 15 Produkte; Doppeltap/Timeout/Retry sicher) | PRESET-001…010, TENANT-* |
| UC-PWR-01 | Wirt hat sein Passwort vergessen: Link anfordern → Mail → Browser-Seite → neues Passwort → Anmeldung am iPad | PWR-001/003/004/008, MAIL-004 |
| UC-PWR-02 | Jemand fischt mit fremden E-Mail-Adressen nach existierenden Konten | PWR-001/002/006 |
| UC-PWR-03 | Reset-Mail kommt spät an, der Wirt hat längst einen neuen Link angefordert | PWR-004 |
| UC-PWR-04 | Passwort war kompromittiert — der Angreifer hält noch ein Refresh-Token | PWR-007 |
| UC-PWR-05 | Wirt vertippt sich beim Wiederholen des Passworts oder wählt es zu kurz | PWR-009 |

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
| GOBD-001 | UC-13 | DB-Grants: scripts/setup-db.ts + **TC-I db-grants.test.ts**; Storno-statt-DELETE: cancellations.test.ts |
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
| GOBD-012 | UC-13/18 | **TC-I db-grants.test.ts** (SHOW GRANTS: keine `.*`-INSERT-Zeile, exakt sechs Tabellen, außer INSERT/USAGE keine Rechte; funktional: `auditDb`-INSERT in `orders` → `ER_TABLEACCESS_DENIED_ERROR`) |
| GOBD-013 | UC-02/18 | **TC-I orders.test.ts** (injizierter Modifier-INSERT-Fehler → 500, `order_items`-Zeile bleibt, `order_item_removals` dokumentiert sie, GET zeigt 0 Positionen, Retry ergibt genau eine Position mit Modifier; Position ohne Modifier läuft nicht durch den Pfad) |
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
| MAIL-009 | UC-MAIL-01/02/04…07 | **TC-U unit/emailTemplates.test.ts** (exakt sechs Registry-Einträge; Pflichtinhalt, Berlin-Zeit, Cent-Format, CTA und HTML-Escaping je Gruppe; alle drei Subscription-Varianten; Z-Bericht-Differenz ±/0) |
| MAIL-010 | UC-MAIL-02/04…07 | **TC-U unit/emailTemplates.test.ts** (`emailIdempotencyKey` deterministisch/tenant-gescoped); **TC-I integration/email-queue.test.ts** (alle fünf S06-Anlassfunktionen und exakte technische Schlüssel, keine Token-/Empfängerwerte) |
| MAIL-011 | UC-MAIL-02 | **TC-M Manuell**: Resend-Domain `verified`, Testmail zugestellt, Header `spf=pass`, `dkim=pass`, `dmarc=pass`, Provider-ID in `email_log`; Runbook `docs/betrieb.md` §4 |
| SORT-001 | UC-16 | **TC-I products.test.ts** (Default exkludiert inaktive; include_inactive=1 inkludiert mit `is_active:false`; Fremd-Tenant-Isolation) |
| SORT-002 | UC-16 | **TC-I products.test.ts** (include_inactive=2 → 400; unbekannter Query-Key → 400) |
| SORT-003 | UC-16 | **TC-I products.test.ts** (expliziter sort_order persistiert; ohne → MAX+10-Append) |
| SORT-004 | UC-16 | **TC-I products.test.ts** (Ordering-Assertion Kategorie→Produkt); **TC-IOS AssortmentSortTests** (Komparator-Tabelle inkl. Tie-Breaker + nil-Kategorie zuletzt), **TC-IOS ModelDecodingTests** (sort_order-Fixtures) |
| SORT-005 | UC-16 | **TC-I products.test.ts** (Reorder happy + idempotent (2×), fremde ID → 404 + unverändert, falsche Kategorie → 404, Duplikate → 422, staff → 403) |
| SORT-006 | UC-16 | Copy-Review SortimentView (Dialogtext beschreibt Soft-Delete + 409-Fall; Server-409-Meldung wird angezeigt) |
| CRON-001 | UC-CRON-01/08 | **TC-U unit/subscriptionDates.test.ts** (Schwellen 9/10/12/13/14, kein Seiteneffekt auf das Datum); **TC-I cron-jobs.test.ts** (Tag 10 + Doppellauf, Tag 13, kein Versand bei jung/abgelaufen/`active`, Tenant ohne aktiven Owner) |
| CRON-002 | UC-CRON-02/08 | **TC-I cron-jobs.test.ts** (Mail + genau ein `audit_log`-Eintrag, Doppellauf ohne zweiten Eintrag, `subscription_status` bleibt `past_due`, innerhalb der Kulanzfrist passiert nichts) |
| CRON-003 | UC-CRON-03/08 | **TC-I cron-jobs.test.ts** (30 h offen → eine Mail, Doppellauf ohne zweite; 2 h und geschlossen bleiben unberührt; Tenant-Isolation-`it()`: jeder Owner bekommt nur die eigene Sitzung) |
| CRON-004 | UC-CRON-04/08 | **TC-I cron-jobs.test.ts** (50 h → Mail + `notified_at`; junge, beendete und bereits gemeldete Ausfälle lösen nichts aus) |
| CRON-005 | UC-CRON-05 | **TC-I cron-jobs.test.ts** (zwei Tenants ohne TSS → beide Einträge requeued statt verworfen, `retry_count` erhöht; Eintrag ohne `receipt_id` failt erst nach Frist); Bestandsabdeckung des gemeinsamen Pfads: offline-queue.test.ts |
| CRON-006 | UC-CRON-06 | **TC-I cron-jobs.test.ts** (failed → genau ein Alert + `alerted_at`; zweiter Lauf 0; `pending` löst nichts aus) |
| CRON-007 | UC-CRON-07 | **TC-U unit/zReportAggregation.test.ts** (`composeZReportJson`: Format identisch zum Abschluss, Nachtrag markiert); **TC-I cron-jobs.test.ts** (Nachtrag mit korrekten Summen, Doppellauf ohne zweiten Bericht, Karenz für frisch geschlossene, vorhandener Bericht bleibt unverändert, offene Sitzung ignoriert) |
| CRON-008 | UC-CRON-01 | **TC-I cron-jobs.test.ts** (eingereihte Mail wird versendet, `email_log`-Nachweis, Inhalte genullt, zweiter Drain leer) |
| CRON-009 | UC-CRON-09 | **TC-U unit/cronRegistry.test.ts** (Cron-Ausdrücke valide, Namen eindeutig, stündliche Jobs entzerrt, Europe/Berlin, `startCron`/`stopCron` idempotent, `CRON_ENABLED=false`, geworfener Job ⇒ `null` statt Prozessende); **TC-U unit/shutdown.test.ts** (Jobs stoppen vor dem Drain) |
| PRESET-001 | UC-17 | **TC-U unit/presetData.test.ts** (Counts, Eindeutigkeit, Referenzen, MwSt.-Leitplanken, recipe_review-Allowlist, exakt 11 Pfandzeilen) |
| PRESET-002 | UC-17 | **TC-I presets.test.ts** (Failure-Injection: History-Fehler ⇒ 500 + inaktiver Rest ohne Historie; gehärteter POST /products ebenso; Happy Path: je Produkt exakt eine initiale History-Zeile) |
| PRESET-003 | UC-17 | **TC-I presets.test.ts** (Replay 200 mit gespeichertem Ergebnis; neuer Key ⇒ alles already_imported; paralleler Doppeltap via Promise.all; Retry nach Fehler ⇒ `repaired`, gleiche Produkt-ID) |
| PRESET-004 | UC-17 | **TC-I presets.test.ts** (deaktiviertes Import-Produkt bleibt nach Re-Import deaktiviert; Namenskollision skip/create) |
| PRESET-005 | UC-17 | **TC-I presets.test.ts** (400/422-Matrix: unbekannter Key, Satzabweichung, review_required, custom_name_required, Float-/0-Preis, vat_confirmed, fehlender Idempotency-Key; Plan-Limit 403; staff 403; Tenant-Isolation-`it()`) |
| PRESET-006 | UC-17 | **TC-I presets.test.ts** (deposit_gate 400 serverseitig, keine Zeile angelegt); **TC-IOS PresetDecodingTests** (isDepositBlocked), Wizard-UI-Sperre |
| PRESET-007 | UC-17 | **TC-I presets.test.ts** (visual_key-Whitelist 422); **TC-IOS VisualCatalogTests** (39 Keys exhaustiv, generic-Fallback, Bundle-Assets vorhanden), **TC-IOS PresetDecodingTests** (unbekannter Key decodiert + rendert generic) |
| PRESET-008 | UC-17 | **TC-IOS VisualSuggestionTests** (alle V1-Presetnamen exakt + Negativfälle: leer, Emoji, nur Menge, Teekanne/Nussecke, Groß-/Kleinschreibung, Umlaute) |
| PRESET-009 | UC-17 | **TC-IOS WizardReviewStateTests** (Sammelbestätigung deckt Risikozeilen nicht; Einzelbestätigung je Zeile; leere Auswahl) |
| PRESET-010 | UC-17 | **TC-I presets.test.ts** (implizit über Happy Path); Audit-Snapshot-Sichtprüfung `audit_log.action = 'preset.imported'` |
| PWR-001 | UC-PWR-02 | **TC-I password-reset.test.ts** (unbekannte E-Mail, unbekanntes Gerät, deaktivierter Nutzer, Drosselung ⇒ je 200 ohne Mail; Treffer- und Fehlantwort byte-gleich) |
| PWR-002 | UC-PWR-02 | **TC-I password-reset.test.ts** (Tenant-Isolation-`it()`s: gleiche E-Mail im Fremdbetrieb bleibt tokenlos; Fremd-Passwort-Hash nach Reset unverändert) |
| PWR-003 | UC-PWR-01 | **TC-U unit/passwordReset.test.ts** (`hashResetToken` ≠ Klartext, 64 Hex; `redactUrl`); **TC-I password-reset.test.ts** (DB hält nur den SHA-256; Token wird aus dem Mailtext gelesen) |
| PWR-004 | UC-PWR-03 | **TC-I password-reset.test.ts** (zweiter Klick, abgelaufen via rückdatiertem `expires_at`, unbekannter Token, neuer Link entwertet alten — je ohne Passwortänderung) |
| PWR-005 | UC-PWR-01 | **TC-I password-reset.test.ts** (Promise.all auf denselben Link ⇒ `{200, 400}`, `used_at` gesetzt) |
| PWR-006 | UC-PWR-02 | **TC-I password-reset.test.ts** (5 Anfragen ⇒ 3 Token, 3 Mails); **TC-U unit/passwordReset.test.ts** (Limit-Konstante) |
| PWR-007 | UC-PWR-04 | **TC-I password-reset.test.ts** (Refresh-Token von vor dem Reset ⇒ 401; danach begonnene Sitzung ⇒ 200; Bestandsnutzer ohne `password_changed_at` ⇒ 200) |
| PWR-008 | UC-PWR-01 | **TC-U unit/passwordReset.test.ts** (kein `<script>`, Token escaped, `noindex`, vollständiges HTML5); **TC-I password-reset.test.ts** (`no-store`, `Referrer-Policy`, GET verbraucht den Token nicht) |
| PWR-009 | UC-PWR-05 | **TC-I password-reset.test.ts** (Wiederholung abweichend ⇒ 422 mit Formular + Token; zu kurz ⇒ 422, danach ist derselbe Link noch gültig) |
| PWR-010 | UC-PWR-01 | **TC-I password-reset.test.ts** (`user.password_reset_requested` + `user.password_reset` im audit_log) |

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

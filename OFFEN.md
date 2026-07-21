# OFFEN — Was noch zu tun ist

**Einzige Quelle für alles Offene.** Stand: 2026-07-20 (inkl. Sortiment-/Trial-Evaluation; Testkonzept: `docs/testkonzept.md`).
Erledigtes fliegt raus (Git-History behält es), Neues kommt priorisiert hier rein.
Spezifikation (DB-Schema, TSE-Flow, Bon-Pflichtfelder): `implementierungsplan.md` §1–15.
**Abarbeitungsreihenfolge (Session-Pakete S01–S21 inkl. S13A/S17A–C + Gates): `ROADMAP.md`** — dort abhaken, hier streichen.

---

## 1. Stand & Audit-Ergebnis (2026-07-10)

Phase 1–4 funktional komplett, Backend 20 Integrationstest-Dateien grün, iOS-App mit allen Screens in Design v3 „Ledger Green". Zweites Finanz-Integritäts-Audit (Fokus: Nicht-Happy-Paths, Races, Retry-Semantik) — **5 Funde gefixt**:

| Fund | Schwere | Fix |
|---|---|---|
| Doppel-Storno-Race: Check lief vor der TX ohne Lock, kein UNIQUE-Constraint → zwei parallele Stornos hätten den Umsatz doppelt negiert (in-App unkorrigierbar, da Storno-von-Storno blockiert) | Kritisch | V008: `UNIQUE(original_receipt_id)` + FOR-UPDATE-Lock auf Original-Bon + Re-Checks in der TX |
| Session-Close-Race: Zahlung, die während `closeSession` committet, landete in geschlossener Session → fehlte im unveränderlichen Z-Bericht → unkorrigierbare Kassendifferenz | Kritisch | closeSession komplett in TX mit Session-Lock; payOrder/splitBill/cancelReceipt sperren die Session-Zeile und geben 409 wenn geschlossen |
| `cancelOrder` ohne Status-Guard im UPDATE → Race gegen payOrder konnte bezahlte Order (mit aktivem Bon!) auf `cancelled` überschreiben | Kritisch | `AND status='open'` + affectedRows-Check → 409 |
| `app_user` hatte pauschales DELETE auf **alle** Tabellen (inkl. receipts, z_reports) — die dokumentierte DB-seitige GoBD-Schutzschicht existierte nicht | Kritisch | setup-db.ts: DELETE nur noch tabellen-scoped auf Nicht-Finanztabellen (Test-DB ausgenommen), inkl. REVOKE für Bestands-DBs. **Prod-DBA-Anweisung entsprechend anpassen!** |
| Z-Bericht `cancellation_count` zählte über die Session der Original-Order statt des Storno-Bons → Folgetag-Storno nettete in Session B, zählte aber in (längst geschlossener) Session A | Mittel | Join über `cancellation_receipt_id` |

Neue Tests: UNIQUE-Backstop (Race-Simulation via Direkt-INSERT), Folgetag-Storno über zwei Sessions (Zählung + Kassenbestand).

### Aus dem Audit offen geblieben (nicht kritisch, einplanen)

| # | Punkt | Warum / Fix-Idee | Prio |
|---|---|---|---|
| A1 | **TSE läuft vor der DB-TX** (payOrder/splitBill/cancelReceipt): verliert die Zahlung danach das 409-Race, existiert ab Phase 2 eine signierte TSE-Transaktion ohne Bon | Vor Phase-2-Go-live: Fiskaly-TX bei Abbruch canceln, oder TSE nach dem Lock (Lock-Dauer abwägen) | Phase 2 |
| A2 | **Fiskaly-4xx blockiert die Zahlung komplett** (kein Offline-Fallback bei Validierungsfehler): ein Schema-Bug nach Fiskaly-API-Änderung würde den ganzen Betrieb lahmlegen, obwohl KassenSichV dokumentierten Offline-Betrieb erlaubt | Design-Entscheidung: 4xx ebenfalls → tse_pending + LAUTER Alert (E-Mail), statt Verkauf zu blockieren | Phase 2 |
| A3 | **addItem: Modifier-INSERTs laufen nach dem Commit** (auditDb, separater Pool): schlägt das fehl → 500, Item ist aber schon drin → Client-Retry erzeugt Duplikat; dem Original fehlen die Modifier-Zeilen (Bon-Nachvollziehbarkeit) | Kompensation: bei Modifier-INSERT-Fehler `order_item_removals`-Eintrag schreiben, dann 500 | Vor Go-live |
| A5 | **Reports: `DATE(CONVERT_TZ(created_at))` in WHERE** ist nicht index-fähig (Full Scan pro Tenant) | Datumsgrenzen in UTC vorberechnen und `created_at BETWEEN ? AND ?` filtern | Nach Pilot |
| A6 | **`audit_insert_user` hat INSERT auf alle Tabellen** statt nur die 5 Audit-Tabellen | Prod: tabellen-scoped Grants (Kommentar in setup-db.ts listet sie) | Vor Go-live |
| A7 | **`changePrice` ohne Lock/TX**: parallele Preisänderungen können Historie-Reihenfolge ≠ finalem Preis erzeugen | Produkt-Zeile FOR UPDATE + Historie und UPDATE seriell | Nach Pilot |
| A9 | **closeSession: z_reports-INSERT nach Commit** (anderer DB-User, keine gemeinsame TX möglich) — schlägt er fehl, ist die Session zu ohne Z-Bericht (wird jetzt laut geloggt, Daten rekonstruierbar) | Cron/Monitoring: geschlossene Sessions ohne z_reports-Zeile finden + nachtragen | Vor Go-live |
| A10 | **Bewusster Trade-off, dokumentieren nicht fixen:** Refresh-Tokens sind stateless — Logout ist rein clientseitig, Session-Kill nur via Geräte-Revoke; 16h-Limit begrenzt den Schaden | — | — |
| A11 | **TSE-Lifecycle startet aktuell erst beim Bezahlen:** `processTseTransaction()` fährt `ACTIVE → FINISHED` vollständig in `payOrder`/`splitBill`; die Bestellung läuft vorher ohne persistierte TSE-TX. § 2 KassenSichV verlangt den Start unmittelbar mit dem aufzuzeichnenden Vorgang; der AEAO nennt auch Bestellungen/nicht abgeschlossene Vorgänge, und Fiskaly weist für Gastronomie auf langlebige `order`-/`Bestellung-V1`-Transaktionen hin. Das ist wichtiger als die Zahlungsart-Frage: Bar, Karte und gemischt werden bereits korrekt als `CASH`/`NON_CASH` übertragen. | Vor Fiskaly-Live fachlich gegen aktuelle DSFinV-K/Fiskaly-Doku + Steuerberater entscheiden und implementieren: Start bei Bestellbeginn bzw. zulässige Erleichterungsregel, persistente TX-ID/Recovery, Abbruch/Timeout/Offline und Bon-Startzeit. Eigenes Paket S13A + Regressionstests. | Phase 2 |

---

## 2. Blocker vor Pilot

Keine. Alle kritischen Audit-Funde sind gefixt, Suites grün. Pilot (Shishabar) kann mit Phase-1-Konfiguration (ohne TSE) testen. A4 (Zahlungs-Retry-UX) ist erledigt (2026-07-19): 409/Timeout beim Bezahlen lädt den Order-Status nach und zeigt den Bon statt einer Sackgasse.

---

## 3. Vor Go-Live — Backend (Code)

Reihenfolge = empfohlene Umsetzungsreihenfolge. E-Mail zuerst, weil Cron-Jobs und Passwort-Reset davon abhängen.

| # | Paket | Inhalt | Aufwand |
|---|---|---|---|
| B1 | **E-Mail-Service** | **Code vollständig 2026-07-20 (S05/S06):** `src/services/email/` (Resend via REST, Queue mit Retry + Idempotenz, `email_log`-Nachweis, Ledger-Green-Layout), alle 6 Template-Gruppen und öffentliche Anlassfunktionen. **Extern offen:** Domain kaufen/festlegen, `mail.<domain>` in Resend mit SPF/DKIM/DMARC verifizieren und Echtmail nach `docs/betrieb.md` §4 zustellen | User-Gate |
| B2 | **Cron-Jobs** (`src/cron.ts`, node-cron, läuft neben index.ts) | Täglich: Trial-Ablauf-Warnung (Tag 10+13), `past_due`-Sperrung nach Grace Period, Sessions >24h offen → Owner-Mail (GoBD), TSE-Ausfall >48h → Meldung + `tse_outages.notified_at`. Stündlich: `failed`-Offline-Queue-Einträge → Alert; **serverseitiger Offline-Queue-Drain** (Nachsignierung darf nicht davon abhängen, dass das iPad wiederkommt); geschlossene Sessions ohne z_report → Alert (A9) | 2 d |
| B3 | **Passwort-Reset** | `POST /auth/forgot-password` + `/reset-password`: Token (einmalig, 1h, gehasht in DB) per Mail, Rate-Limit, kein User-Enumeration-Leak (immer 200) | 1 d |
| B4 | **`versionMiddleware`** | `X-App-Version`-Header, semver-Vergleich gegen `devices.min_app_version` → 426; iOS zeigt Update-Hinweis | 0,5 d |
| B5 | **`GET /tenants/me` Subscription-Details** | `trial_expires_at`, `subscription_current_period_end` in Response; iOS EinstellungenView zeigt Trial-Restzeit + Banner ab Tag 10 | 0,5 d |
| B6 | ~~**Prozess-Härtung**~~ | Erledigt 2026-07-19 (S03): `src/shutdown.ts` (Drain → Sentry-Flush → Pools, idempotent, 10-s-Notbremse), SIGTERM/SIGINT + `unhandledRejection`/`uncaughtException` in `index.ts`, Pino statt console. Nachweis-Protokolle in `docs/betrieb.md` §2. **Achtung bei S20:** PM2 `kill_timeout: 15000` / systemd `TimeoutStopSec=15`, sonst wirkungslos | ✅ |
| B7 | ~~**`.env.example` vervollständigen**~~ | Erledigt 2026-07-19 (S03): `ALLOWED_ORIGIN`, `LOG_LEVEL`, `SENTRY_DSN` ergänzt | ✅ |
| B8 | **A3 + A6 + A9** aus dem Audit | s.o. | 1 d |
| B9 | **Trial-/Entitlement-Härtung** | 14-Tage-Trial existiert, ist aber nicht launch-sicher: Plan-Auswahl im iOS-Onboarding wird nicht gespeichert (Tenant bleibt `starter`), Copy verspricht automatische Umstellung trotz „keine Kreditkarte“, und die pauschale `subscriptionMiddleware` blockiert nach Ablauf auch sichere Abschluss-/Lesewege wie Session-Schluss, Sync, Bons und Export. Entscheidung: kein permanenter Live-Free-Tier; 14 Tage ohne Kreditkarte, Start erst bei bewusster Aktivierung/erster Kassensitzung, danach kein Auto-Charge. Explizite Entitlement-Matrix: keine neue Schicht nach Ablauf, aber offene Schicht sicher beenden, TSE nachsignieren, Bons/DSFinV-K lesen/exportieren und Billing erreichen. | 1,5–2 d |

---

## 4. Vor Go-Live — Nicht-Code

| # | Punkt | Hinweis |
|---|---|---|
| N1 | **DB-Backup-Strategie** | GoBD: 10 Jahre Aufbewahrung — **Pflicht, kein Nice-to-have.** Nightly Dump + Offsite (z.B. Hetzner Storage Box), Restore-Test dokumentieren. Ohne Backup-Konzept keine Verfahrensdokumentation |
| N2 | **Fiskaly Live** | Live-Account, TSS für Shishabar anlegen, TSE-Client je iPad; Phase-2-Code-Pfade (A1, A2, A11) vorher lösen |
| N3 | **ELSTER** | Kassen-Anmeldung (einmalig, manuell) — Pflicht seit 2025 |
| N4 | **Stripe Live** | Live-Keys, Webhook-Endpoint im Dashboard, Preis-IDs für 3 Pläne |
| N5 | **Hosting** | Hetzner, Nginx + SSL, PM2 (Cluster erst nach Rate-Limit-Store-Fix §7), GitHub Actions CI/CD (Suites + tsc als Gate) |
| N6 | **MariaDB Prod-Setup** | Timezone-Tabellen laden (`mariadb-tzinfo-to-sql`, sonst liefern alle Berichte 0!), DB-User nach setup-db.ts-Vorbild inkl. **kein DELETE für app_user** |
| N7 | ~~**Apple Developer Account**~~ | ✅ vorhanden (2026-07-19). Nächster Schritt: TestFlight-Build. T7 ist geklärt (App-Min = iPadOS 26.2) — **vorher am Pilot-iPad prüfen, dass iPadOS 26 läuft bzw. installierbar ist** |
| N8 | **Rechtliches** | AGB + Haftung (Anwalt), AVV-Vorlage, **Verfahrensdokumentation** (GoBD-Pflicht vor Go-live), schriftliche Pilot-Vereinbarung, Datenhaltung nach Kündigung |
| N9 | **Steuerberater** | receipt_sequences-Konzept absegnen, Offline-TSE-Handling absegnen; Trinkgeld (vor Phase 3), Außer-Haus-MwSt (vor Phase 4) |

---

## 5. Arbeitspaket: E-Mails (B1)

**Code vollständig (S05/S06, 2026-07-20).** Entschieden: **Resend** (REST via `fetch`, kein SDK — eine
Abhängigkeit weniger). Implementiert in `backend/src/services/email/`:

| Datei | Inhalt |
|---|---|
| `send.ts` | Resend-REST-Aufruf, 15-s-Timeout; **ohne `RESEND_API_KEY` Dry-Run** (Dev/CI versenden nie nach außen) |
| `queue.ts` | `enqueueMail` (INSERT IGNORE auf `idempotency_key`) + `drainEmailQueue` (atomarer Claim, Backoff 1/5/15/60/240 min, `failed` + Sentry nach `max_attempts`, Stuck-Reset nach 10 min) |
| `templates.ts` | Registry `TemplateName → Builder`; 6 Gruppen vollständig, Subscription-Events als typsichere Varianten `past_due` / `cancelled` / `reactivated` |
| `layout.ts` / `palette.ts` / `format.ts` | Ledger-Green-Bausteine, `euroString` in Frontend-Parität |
| `index.ts` | Öffentliche Anlass-Funktionen für Trial, TSE-Ausfall, Passwort-Reset, Z-Bericht, Subscription-Events und Session >24 h |

**Zwei Tabellen mit getrennten Rollen (V009):** `email_queue` operativ/UPDATE-bar (Inhalte werden nach
Erfolg genullt — DSGVO), `email_log` INSERT-only via `audit_insert_user` (Versandnachweis mit
`provider_message_id`, Pflicht bei KassenSichV-Meldemails).

**Noch offen (externes Gate):** Hauptdomain festlegen/kaufen, `mail.<domain>` in Resend per
SPF/DKIM/DMARC verifizieren, `MAIL_FROM`/`RESEND_API_KEY` in Prod setzen und eine Echtmail samt
`email_log`-Nachweis zustellen (`docs/betrieb.md` §4). Drain per Cron kommt in S07 — bisher ruft
niemand `drainEmailQueue` periodisch auf.

**Design:** HTML-Templates im Ledger-Green-Look, Tokens aus `DesignSystem.swift` gespiegelt:
- Palette: Ledger-Green-Primär, Brass-Akzent, olivgetönte Neutrals (Hex-Werte aus DS.C übernehmen)
- Typo: System-Stack (`-apple-system, 'SF Pro Text', 'Segoe UI', sans-serif`), Geldbeträge tabellarisch/monospaced, deutsche Formatierung (1.234,56 €) — identisch zu `euroString()`
- Layout: 600px, Single Column, Bulletproof-Buttons, Dark-Mode via `prefers-color-scheme`, Plaintext-Fallback je Template
- Absender: `noreply@<domain>`, SPF/DKIM/DMARC einrichten (sonst landet die KassenSichV-Pflichtmail im Spam)

**Templates (je: Betreff, HTML, Plaintext):**
1. ~~Trial-Warnung (Tag 10 + 13) — Restzeit, Plan-CTA~~ ✅ erledigt (S05)
2. ~~TSE-Ausfall >48h — Pflichtmeldung mit Ausfallzeitraum, betroffenem Gerät, Handlungsanweisung (ELSTER-Meldung)~~ ✅ S06
3. ~~Passwort-Reset — Token-Link, 1h-Hinweis~~ ✅ S06
4. ~~Z-Bericht-Tageszusammenfassung (opt-in) — Umsatz, Zahlarten, Differenz~~ ✅ S06
5. ~~Subscription-Events — Zahlung fehlgeschlagen (past_due), Kündigung bestätigt (+ Datenexport-Hinweis), Reaktivierung~~ ✅ S06
6. ~~Session >24h offen — GoBD-Warnung an Owner~~ ✅ S06

---

## 6. Arbeitspaket: Frontend-Exzellenz (impeccable)

**Großer Pass erledigt (2026-07-11, Design v3.1):** Impeccable-Review (2× Design-Assessment + Native-Audit) + Umsetzung. Erledigt: Kiosk-Lock (iPad-only, Vollbild, Landscape — **kein iPhone/Split View mehr, bewusste Entscheidung**); Dynamic Type app-weit via `.dsFont(…)` (gedeckelt auf AX1); VoiceOver-Grundausstattung (MoneyText liest Beträge natürlich, Tischkacheln kombiniert, Icon-Buttons gelabelt); Karte-Zahlung ehrlich als 2-Schritt (kein „Warte auf Terminal"-Fake mehr); Kassenzählung befüllt Abschluss-Sheet vor; Onboarding mit Ausstieg + erzwungener Pflicht-Checkliste (vatId/Standort-Felder entfernt — Backend nahm sie nie an; USt-IdNr. pflegbar in Einstellungen → Betriebsdaten); durchgängig Du; Fake-Status/“Phase N“-Jargon/tote Stub-Buttons raus; DSTextField/DSSheetScaffold/DSSegmentedControl/DSSkeleton/Haptics als Shared-Komponenten; Skeletons an den 4 Kern-Ladezuständen; Erfolgs-Checkmark + Haptik bei Zahlung/„Kasse stimmt“; Bar-Zahlung mit „passend“-Prefill (0-Tap-Default); Appearance System/Hell/Dunkel (Default System); Reduce-Motion-Crossfades; Touch-Targets ≥44pt (Qty, Chips, Pills); Jakarta-TTFs + tote Font-APIs gelöscht.

**Offen geblieben (nächster Pass):**
- **Fehler mit Retry:** Alerts haben weiterhin nur „OK" — Retry-Button + `AppError.failureReason` als Sekundärzeile anzeigen
- Offline-UX: jede schreibende Aktion muss offline klar sagen, was passiert (Queue vs. blockiert)
- Haptik auf Storno fehlt noch (Zahlung/Session-Schluss/Numpad/Segmente haben sie)
- Dynamic-Type-AX1-Screenshotmatrix aller Screens (Login hell/dunkel verifiziert; Rest manuell testen — kein Test-Target)
- Session-Ablauf (16h-Limit): forceLogout darf keinen Warenkorb verlieren — Zustand sichern
- OrderView: Warenkorb-Performance bei 50+ Positionen, Produkt-Grid-Suche fehlt
- PaymentView: Rückgeld noch größer/zuerst (aktuell Zeile + Confirm-Label), Gemischt-Live-Validierung
- TableOverview: Auto-Refresh-Intervall (Stale-Daten nach App-Wechsel; Pull-to-Refresh existiert)
- ZBericht/Berichte: Differenz-Farblogik (rot erst ab Schwelle, nicht bei ±1 Cent)
- Onboarding: Wiedereinstieg bei Abbruch auf Schritt 4 (State-Persistenz)
- EInputRow (Einstellungen-Zeilenfeld) bewusst nicht auf DSTextField (anderes Layoutmuster) — bei Gelegenheit angleichen
- **Betriebshinweis Kiosk:** `UIRequiresFullScreen` ist von Apple als „wird künftig ignoriert" markiert — echter Kiosk-Betrieb beim Piloten über Guided Access (Dreifachklick) bzw. später MDM Single App Mode

### Sortiment & Betreiber-Aktivierung (evaluiert 2026-07-20)

**Nutzungsszene:** Ein Mitarbeiter tippt im gedimmten, lauten Gastro-Betrieb unter Zeitdruck auf ein
Landscape-iPad. Er braucht stabile Positionen, große Ziele und eindeutige Farb-/Symbolhinweise; eine
foto-lastige Speisekarte darf die Kasse nicht langsamer oder unruhiger machen.

- ~~**UX-S1 — Fundament**~~ **erledigt 2026-07-21 (S17A):** `GET /products?include_inactive=1`
  (Management; Kasse bleibt active-only), `products.sort_order` (V010) + `sort_order` auf
  `ProductCategoryRef`/`Product` bis SwiftUI, deterministische Sortierung (Backend-SQL == iOS
  `assortmentSorted`), Reorder-Endpoints (`PATCH /products/reorder` + `/categories/reorder`),
  Kategorie-Löschtext an 409-Verhalten angeglichen. Tests: REQ-SORT-001…006.
- ~~**UX-S2 — Ein gemeinsamer Bereich „Sortiment"**~~ **erledigt 2026-07-21 (S17A):**
  `SortimentView` ersetzt ProdukteView + KategorienView (NavItem `.sortiment`): Kategorienleiste
  links, Kassenansicht (echte `ProductCard`-Kacheln) / Liste, Suche, Aktiv/Inaktiv-Filter,
  Inline-Kategorieanlage, Reihenfolge-Modus (native List + `.onMove`, VoiceOver-Rearrange),
  Quick-Create Name+Preis+Kategorie mit „Weitere Einstellungen" (DisclosureGroup).
- ~~**UX-S3 — Starter-Sortimente**~~ **erledigt 2026-07-21 (S17B):** `GET /products/presets` +
  `POST /products/presets/import` (Idempotency-Key, `preset_imports`-Claim, Origin-UNIQUE je Tenant),
  gemeinsamer GoBD-Produktservice `createProductWithHistory` (inaktiv → Historie → Verify → aktiv —
  härtet auch `POST /products`), 8-Schritte-Wizard (`SortimentWizardView`) mit ausdrücklicher
  MwSt.-Bestätigung (Sammel nur für Standardzeilen, Einzelbestätigung für `recipe_review`/
  `printed_price_review`). V1-Daten exakt nach `docs/s17-sortiment-starterpakete.md`. Vertrag: `docs/api.md`.
- ~~**UX-S4 — Visuals V1**~~ **erledigt 2026-07-21 (S17B):** 39 semantische `visual_key`s
  (`products.visual_key`, Whitelist serverseitig), `ProduktVisualCatalog` (SF Symbols + 4 eigene
  monochrome Template-Assets, generic-Fallback für unbekannte Keys), Namensheuristik als Picker-
  Vorbelegung (`VisualSuggestion.swift`, nie automatisch überschreibend), Kachel mit und ohne Visual
  gleichwertig. **Stufe 2 (eigene Fotos/Object Storage) bleibt bewusst nach Go-live** — siehe §9/Backlog.
- ~~**UX-S5 — Pfand-Gate für Späti**~~ **Gate aktiv seit 2026-07-21 (S17B):** die elf
  `deposit_cents=25`-Zeilen werden server- (400 `deposit_gate`) und UI-seitig (gesperrte Zeile
  „Pfandfunktion erforderlich") abgewiesen; Pfand steckt nie in `price_cents`. **Offen bleibt das
  separate, finanziell auditierte Pfand-Paket** (getrennter Ausweis, signierte Pfandrückgabe,
  Bon/TSE-Abbildung) — erst danach werden die Späti-Pfandzeilen freigeschaltet (Spec §5.4).

**Zielmetrik:** Ein neuer Betreiber hat in unter 10 Minuten mindestens 3 Kategorien und 15 verkaufsfertige,
sortierte Produkte; der Kassenbetrieb bleibt auch komplett ohne Bilder hochwertig und schnell.

---

## 7. Tests & Qualität

Testkonzept (REQ → UC → TC, Traceability): **`docs/testkonzept.md`** — neue Anforderungen dort als REQ eintragen, jedem REQ ≥ 1 TC zuordnen.
Erledigt 2026-07-19: T1 (5 Unit-Dateien: splitPartition, cancellationNegation, zReportAggregation, sequences, fiskalyPayload), T2 (XCTest-Target `zettel-frontendTests`, 40 Tests: ParseCents, EuroString, PaymentLogic, VatBreakdown-Formelparität, ModelDecoding — der Roundtrip-Test fand direkt einen Tausenderpunkt-Bug in parseCents), T3 (`integration/e2e-tagesablauf.test.ts`), T4 (`integration/concurrency.test.ts` — echte Promise.all-Races gegen pay/cancel/close/open).

| # | Lücke | Inhalt | Prio |
|---|---|---|---|
| T5 | ~~**CI**~~ | Erledigt 2026-07-19: Backend-Job (S01) + iOS-Job (S02) in `.github/workflows/ci.yml`, beide Required Status Checks auf `main`. Doku `docs/ci.md` | ✅ |
| T7 | ~~**Test-Target verlangt iOS 26.2, App nur 18.2**~~ | Entschieden + umgesetzt 2026-07-20: **App-Mindestversion auf iOS 26.2 angehoben** (Niko-Entscheidung: nur aktuelles iPadOS ab 26 unterstützen), nicht das Test-Target gesenkt. Alle vier Build-Configs (App + `zettel-frontendTests`, Debug + Release) stehen jetzt einheitlich auf `IPHONEOS_DEPLOYMENT_TARGET = 26.2`; das Test-Target lief zusätzlich auf `TARGETED_DEVICE_FAMILY = "1,2"` und ist jetzt wie die App auf `2` (iPad-only). Damit testen App und Tests dieselbe Mindestversion, und `macos-26` in CI ist Konsequenz statt offener Punkt (Preview-Status bewusst akzeptiert). Nachweis: 40 XCTests grün auf iPad Pro 11" (M5), iOS 26.3. **Folge für S04:** das Pilot-iPad muss iPadOS 26 laufen können (iPad Pro ab A12X, iPad Air ab 3. Gen, iPad ab 8. Gen, iPad mini ab 5. Gen) — vor dem TestFlight-Build prüfen | ✅ |
| T9 | ~~**Report-Tests nachts 2 h flaky (UTC vs. Europe/Berlin)**~~ | Gefunden + behoben 2026-07-20 (während S03, um 00:13 CEST aufgeschlagen). `reports.test.ts`/`cancellations.test.ts` berechneten „heute" als **UTC**-Datum (`toISOString().slice(0,10)`), die Berichte bucketen aber via `CONVERT_TZ` nach **Europe/Berlin**. Zwischen 00:00–02:00 Berliner Zeit (22:00–24:00 UTC) laufen die Daten auseinander → Tests fragen den Vortag ab, bekommen korrekt 0, werden rot. **Die Berichtslogik war richtig** — nur die Tests lagen falsch. Relevanz: CI läuft in UTC, das PR-Gate aus S01 wäre jede Nacht 2 h lang unzuverlässig gewesen. Fix: `berlinDate()`/`berlinDateDaysAgo()` in `testHelpers.ts`; die UTC-Idiom-Stellen in `products`/`receipts-list`/`export` sind unkritisch (Berechtigung bzw. 60-Tage-Abstand, `exportController` nutzt kein CONVERT_TZ) und blieben unverändert | ✅ |
| T8 | **`npm run dev` startet nicht** | `ts-node src/index.ts` scheitert im CommonJS-Modus an den `.js`-Endungen der relativen Imports (`Cannot find module './sentry.js'`) — betrifft jeden Import in `index.ts`, nicht nur den neuen. Bestandsproblem, bei S03 aufgefallen, weil dort erstmals lokal gestartet wurde. Tests laufen über vitest (löst korrekt auf), Produktion über `npm run build` + `npm start` — deshalb bisher unbemerkt. Fix: `tsx` statt `ts-node` als dev-Runner (löst `.js`→`.ts` auf), oder ts-node ESM-Loader. Nicht dringend, aber jeder neue Entwickler stolpert sofort darüber (vgl. S5 Docker Compose) | Gelegenheit / vor S5 |
| T10 | ~~**Testläufe melden echte Events ans Produktions-Sentry**~~ | Gefunden + behoben 2026-07-20 (bei S05). `src/sentry.ts` rief `dotenv.config()` ohne Pfad und lud damit immer `.env`, nie `.env.test` — lokal steht dort seit S03 ein echter DSN, also ging jeder Testfehler ins EU-Produktionsprojekt (aufgefallen, weil der `failed`-Pfad der E-Mail-Queue `captureException` ruft). In CI war es harmlos (kein `.env`), lokal verfälschte es genau das Dashboard, auf dem die Alert-Regel sitzt. Fix: derselbe Pfad-Switch wie in `db/index.ts`; Regressionsschutz in `unit/sentryConfig.test.ts` (schlägt an, wenn der Switch verschwindet **oder** jemand einen DSN in `.env.test` einträgt). Log sagt im Testlauf jetzt „Sentry deaktiviert" | ✅ |
| T6 | **Backend: `any` eliminieren (237 Stellen, davon 160 `db.execute<any[]>`)** | Request-Seite ist via Zod schon typisiert (`z.infer`), die DB-Seite nicht. Plan: (1) Row-Interfaces pro Tabelle in `src/db/types.ts` (`OrderRow`, `ReceiptRow`, …) und `db.execute<OrderRow[]>` — Achtung: mysql2-Generics sind reine Casts, keine Runtime-Prüfung, daher Spalten-Drift weiter durch Integrationstests absichern; (2) `ResultSetHeader` statt `<any>` für INSERT/UPDATE-Ergebnisse; (3) `catch (err: unknown)` + Narrowing statt `err: any`; (4) ESLint `@typescript-eslint/no-explicit-any: error` als Ratchet, Geld-Pfade zuerst (payments, splitBill, cancellations, sessions). iOS ist sauber (nur KeychainHelper nutzt `[String: Any]` — Security-C-API, unvermeidbar) | Vor Go-live, schrittweise |

---

## 8. Stabilität / Performance / Robustheit

| # | Punkt | Warum | Prio |
|---|---|---|---|
| S1 | ~~**Error-Monitoring (Sentry)**~~ | Erledigt 2026-07-19 (S03): `src/sentry.ts` (`@sentry/node` v10), captureException im globalen Error-Handler — nur 5xx, Kontext tenant/url/method, keine PII. Ohne `SENTRY_DSN` komplett aus. Doku `docs/betrieb.md` §1. **Rest-Aufgabe User:** Sentry-Projekt anlegen, DSN in Prod-`.env`, Alert-Regel setzen | ✅ |
| S2 | **Rate-Limit: in-memory Store** | Reset bei Restart, nicht Cluster-fähig (PM2), per-IP statt per-Tenant (NAT-Problem) → Redis-Store + keyGenerator nach tenantMiddleware | Vor Multi-Instanz |
| S3 | **subscriptionMiddleware: DB-Query pro Request** | Status in JWT-Claim, DB nur bei `trial` | Nach Pilot |
| S4 | **A5: Report-Queries nicht index-fähig** | s. Audit | Nach Pilot |
| S5 | **Docker Compose** | Onboarding zweiter Entwickler / neues Gerät | Gelegenheit |
| S6 | **DB-Pool-Sizing + Timeouts prüfen** | Session-Locks serialisieren Zahlungen pro Gerät — bei Multi-Tenant-Last Pool-Größe & `innodb_lock_wait_timeout` bewusst setzen | Vor Go-live |
| S7 | **Server überlebt `EADDRINUSE` stillschweigend** | `src/index.ts:78` behandelt kein `error`-Event auf `server.listen()`. Beobachtet 2026-07-20: Port war belegt, Prozess lief 2,5 min weiter **ohne auf irgendeinem Port zu lauschen** und ohne sichtbaren Fehler. In Prod heißt das: Deploy meldet „läuft", Kasse ist tot. → `server.on('error')` mit Fatal-Log + Exit 1 | Vor Go-live |
| S8 | **`/health` sagt nicht, wessen Server antwortet** | Antwort ist generisch (`{status, timestamp}`). Bei belegtem Port antwortet ein fremder Dienst mit 200 und die Diagnose läuft in die Irre (real passiert 2026-07-20). → Feld `service: "cashbox"` + Version in die Antwort | Gelegenheit |
| S9 | **422-`details` sind englische Zod-Rohtexte** | `validationMiddleware` reicht `result.error.flatten().fieldErrors` durch („Invalid input: expected string…"). iOS zeigt deshalb nur die Feldnamen als Diagnose, nicht *was* falsch ist. → deutsche Messages in den Zod-Schemas (`.min(8, 'Passwort braucht mindestens 8 Zeichen')`) | Nach Pilot |

---

## 9. Differenzierung — was die App besser macht

Nikos Insider-Blick (Deutsche Post ITS, POS-Testing) gezielt nutzen — die Punkte, an denen etablierte Kassensysteme (orderbird, ready2order, Gastrofix) im Alltag schwächeln:

1. **Ehrliche Offline-Story.** Wettbewerber verstecken den Offline-Zustand; wir zeigen Queue-Stand transparent (Banner + pendingCount) und signieren nach. Ausbaustufe: Bestellen/Kassieren komplett offline mit lokaler Queue (Phase 3 SyncManager-Vollausbau)
2. **Geschwindigkeit als Feature.** PIN-Wechsel <1s, Zahlung in 2 Taps, keine Lade-Spinner im Kassier-Flow. Messbar machen: Time-to-Receipt als internes SLO
3. **Z-Bericht-Mail am Morgen** (§5 Template 4) — der Wirt sieht den Vortag ohne die App zu öffnen. Klingt klein, ist im Alltag das Feature, über das man spricht
4. **Compliance ohne Angst:** Bon-Nummern lückenlos, Storno-Gegenbuchung, DSFinV-K auf Knopfdruck — als UI-Story erzählen („Betriebsprüfungs-Modus": Export + Verfahrensdoku-Checkliste), nicht nur als Backend-Fakt
5. **Faires SaaS:** Datenexport nach Kündigung (30-Tage-ZIP, noch zu bauen), keine Hardware-Bindung, Pilot-Preismodell
6. Später: DATEV-Export (Steuerberater lieben es → Empfehlungskanal), Multi-iPad, Bondrucker (Phase 5)

---

## 10. Priorisierte Reihenfolge

1. **Jetzt (Pilot läuft an):** Pilot-Feedback-Schleife (A4 + T1–T4 sind erledigt, 2026-07-19)
2. **Vor Go-live (Reihenfolge):** B1 E-Mail → B2 Cron → B3 Passwort-Reset → B6/B7 Prozess-Härtung → B4/B5 → A3/A6/A9 → S1/S6 → N1–N9 parallel (Rechtliches/Fiskaly/ELSTER haben Vorlauf!)
3. **Phase 2 (TSE scharf):** A1 + A2 + A11 lösen → Fiskaly-Sandbox-E2E → N2/N3
4. **Nach Pilot:** §6 impeccable-Pass komplett, T5, S2–S4
5. **Vor öffentlichem Go-live:** B9 (S17C) — UX-S1–S5 erledigt 2026-07-21 (S17A/S17B); Späti-Pfandzeilen bleiben bis zum separaten Pfand-Paket gesperrt
6. **Phase 3+:** Eigene Produktfotos/digitales Menü, Trinkgeld (nach Steuerberater), SyncManager-Vollausbau, Phase-5-Features

---

*Pflege: Nach jeder Änderung erledigte Punkte hier streichen (CLAUDE.md-Regel). Neue Erkenntnisse mit Prio + Warum eintragen — nicht nur Was.*

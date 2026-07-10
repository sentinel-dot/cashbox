# OFFEN — Was noch zu tun ist

**Einzige Quelle für alles Offene.** Stand: 2026-07-10 (nach Finanz-Integritäts-Audit).
Erledigtes fliegt raus (Git-History behält es), Neues kommt priorisiert hier rein.
Spezifikation (DB-Schema, TSE-Flow, Bon-Pflichtfelder): `implementierungsplan.md` §1–15.

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
| A4 | **iOS: 409 nach Zahlungs-Timeout-Retry** — wenn der erste Request serverseitig durchkam, sieht der Kellner nur „Bestellung ist nicht mehr offen" und keinen Bon. Geld ist sicher (Statusmaschine), UX nicht | PaymentView: bei 409 Order-Status nachladen; wenn `paid` → Bon anzeigen statt Fehler | Vor Pilot-Ende |
| A5 | **Reports: `DATE(CONVERT_TZ(created_at))` in WHERE** ist nicht index-fähig (Full Scan pro Tenant) | Datumsgrenzen in UTC vorberechnen und `created_at BETWEEN ? AND ?` filtern | Nach Pilot |
| A6 | **`audit_insert_user` hat INSERT auf alle Tabellen** statt nur die 5 Audit-Tabellen | Prod: tabellen-scoped Grants (Kommentar in setup-db.ts listet sie) | Vor Go-live |
| A7 | **`changePrice` ohne Lock/TX**: parallele Preisänderungen können Historie-Reihenfolge ≠ finalem Preis erzeugen | Produkt-Zeile FOR UPDATE + Historie und UPDATE seriell | Nach Pilot |
| A8 | **`parseCents` doppelt implementiert** (KassensitzungView, ProdukteView — einmal `Int?`, einmal `Int`) | Eine zentrale Funktion in DesignSystem.swift | Gelegenheit |
| A9 | **closeSession: z_reports-INSERT nach Commit** (anderer DB-User, keine gemeinsame TX möglich) — schlägt er fehl, ist die Session zu ohne Z-Bericht (wird jetzt laut geloggt, Daten rekonstruierbar) | Cron/Monitoring: geschlossene Sessions ohne z_reports-Zeile finden + nachtragen | Vor Go-live |
| A10 | **Bewusster Trade-off, dokumentieren nicht fixen:** Refresh-Tokens sind stateless — Logout ist rein clientseitig, Session-Kill nur via Geräte-Revoke; 16h-Limit begrenzt den Schaden | — | — |

---

## 2. Blocker vor Pilot

Keine. Alle kritischen Audit-Funde sind gefixt, Suites grün. Pilot (Shishabar) kann mit Phase-1-Konfiguration (ohne TSE) testen. A4 (Zahlungs-Retry-UX) sollte während des Piloten kommen — genau dieser Fall (WLAN-Aussetzer beim Bezahlen) passiert in einer Shishabar ständig.

---

## 3. Vor Go-Live — Backend (Code)

Reihenfolge = empfohlene Umsetzungsreihenfolge. E-Mail zuerst, weil Cron-Jobs und Passwort-Reset davon abhängen.

| # | Paket | Inhalt | Aufwand |
|---|---|---|---|
| B1 | **E-Mail-Service** | Siehe Arbeitspaket §5 (Resend/Postmark + Ledger-Green-Templates) | 2–3 d |
| B2 | **Cron-Jobs** (`src/cron.ts`, node-cron, läuft neben index.ts) | Täglich: Trial-Ablauf-Warnung (Tag 10+13), `past_due`-Sperrung nach Grace Period, Sessions >24h offen → Owner-Mail (GoBD), TSE-Ausfall >48h → Meldung + `tse_outages.notified_at`. Stündlich: `failed`-Offline-Queue-Einträge → Alert; **serverseitiger Offline-Queue-Drain** (Nachsignierung darf nicht davon abhängen, dass das iPad wiederkommt); geschlossene Sessions ohne z_report → Alert (A9) | 2 d |
| B3 | **Passwort-Reset** | `POST /auth/forgot-password` + `/reset-password`: Token (einmalig, 1h, gehasht in DB) per Mail, Rate-Limit, kein User-Enumeration-Leak (immer 200) | 1 d |
| B4 | **`versionMiddleware`** | `X-App-Version`-Header, semver-Vergleich gegen `devices.min_app_version` → 426; iOS zeigt Update-Hinweis | 0,5 d |
| B5 | **`GET /tenants/me` Subscription-Details** | `trial_expires_at`, `subscription_current_period_end` in Response; iOS EinstellungenView zeigt Trial-Restzeit + Banner ab Tag 10 | 0,5 d |
| B6 | **Prozess-Härtung** | SIGTERM-Handler (Server drainen, DB-Pools schließen), `unhandledRejection`/`uncaughtException`-Handler (loggen + kontrolliert beenden — Node crasht sonst hart), `index.ts` auf Pino statt console | 0,5 d |
| B7 | **`.env.example` vervollständigen** | `ALLOWED_ORIGIN` (CORS Prod), `LOG_LEVEL` — Code liest beide, Example kennt sie nicht | 10 min |
| B8 | **A3 + A6 + A9** aus dem Audit | s.o. | 1 d |

---

## 4. Vor Go-Live — Nicht-Code

| # | Punkt | Hinweis |
|---|---|---|
| N1 | **DB-Backup-Strategie** | GoBD: 10 Jahre Aufbewahrung — **Pflicht, kein Nice-to-have.** Nightly Dump + Offsite (z.B. Hetzner Storage Box), Restore-Test dokumentieren. Ohne Backup-Konzept keine Verfahrensdokumentation |
| N2 | **Fiskaly Live** | Live-Account, TSS für Shishabar anlegen, TSE-Client je iPad; Phase-2-Code-Pfade (A1, A2) vorher lösen |
| N3 | **ELSTER** | Kassen-Anmeldung (einmalig, manuell) — Pflicht seit 2025 |
| N4 | **Stripe Live** | Live-Keys, Webhook-Endpoint im Dashboard, Preis-IDs für 3 Pläne |
| N5 | **Hosting** | Hetzner, Nginx + SSL, PM2 (Cluster erst nach Rate-Limit-Store-Fix §7), GitHub Actions CI/CD (Suites + tsc als Gate) |
| N6 | **MariaDB Prod-Setup** | Timezone-Tabellen laden (`mariadb-tzinfo-to-sql`, sonst liefern alle Berichte 0!), DB-User nach setup-db.ts-Vorbild inkl. **kein DELETE für app_user** |
| N7 | **Apple Developer Account** | 99 €/Jahr, TestFlight für Pilot |
| N8 | **Rechtliches** | AGB + Haftung (Anwalt), AVV-Vorlage, **Verfahrensdokumentation** (GoBD-Pflicht vor Go-live), schriftliche Pilot-Vereinbarung, Datenhaltung nach Kündigung |
| N9 | **Steuerberater** | receipt_sequences-Konzept absegnen, Offline-TSE-Handling absegnen; Trinkgeld (vor Phase 3), Außer-Haus-MwSt (vor Phase 4) |

---

## 5. Arbeitspaket: E-Mails (B1)

**Service:** Resend oder Postmark (REST, kein SMTP-Gefrickel). `src/services/email.ts` mit Template-Registry, Versand-Log in neuer Tabelle `email_log` (INSERT-only: tenant_id, template, recipient, sent_at, provider_message_id) — bei KassenSichV-Meldemails muss der Versand nachweisbar sein. Fehlversand → Retry via Queue-Pattern analog offline_queue.

**Design:** HTML-Templates im Ledger-Green-Look, Tokens aus `DesignSystem.swift` gespiegelt:
- Palette: Ledger-Green-Primär, Brass-Akzent, olivgetönte Neutrals (Hex-Werte aus DS.C übernehmen)
- Typo: System-Stack (`-apple-system, 'SF Pro Text', 'Segoe UI', sans-serif`), Geldbeträge tabellarisch/monospaced, deutsche Formatierung (1.234,56 €) — identisch zu `euroString()`
- Layout: 600px, Single Column, Bulletproof-Buttons, Dark-Mode via `prefers-color-scheme`, Plaintext-Fallback je Template
- Absender: `noreply@<domain>`, SPF/DKIM/DMARC einrichten (sonst landet die KassenSichV-Pflichtmail im Spam)

**Templates (je: Betreff, HTML, Plaintext):**
1. Trial-Warnung (Tag 10 + 13) — Restzeit, Plan-CTA
2. TSE-Ausfall >48h — Pflichtmeldung mit Ausfallzeitraum, betroffenem Gerät, Handlungsanweisung (ELSTER-Meldung)
3. Passwort-Reset — Token-Link, 1h-Hinweis
4. Z-Bericht-Tageszusammenfassung (opt-in) — Umsatz, Zahlarten, Differenz; der tägliche Berührungspunkt, der die App vom Wettbewerb abhebt
5. Subscription-Events — Zahlung fehlgeschlagen (past_due), Kündigung bestätigt (+ Datenexport-Hinweis), Reaktivierung
6. Session >24h offen — GoBD-Warnung an Owner

---

## 6. Arbeitspaket: Frontend-Exzellenz (impeccable)

Screen-für-Screen-Pass mit `/impeccable` (audit.native + ios-Referenz + polish). Nicht „hübscher machen", sondern die Punkte, an denen POS-Apps im Alltag nerven:

**Querschnitt (alle Screens):**
- **Fehlerpfade zuerst:** Jeder Netzwerk-Call braucht die drei Zustände Loading (Skeleton statt Spinner wo möglich), Fehler (mit Retry-Button, nicht nur Alert), Leer (DSEmptyState mit Handlungsaufforderung). Aktuell primär Alert-basiert
- **A4 aus dem Audit:** 409/Timeout-Recovery beim Bezahlen (Status nachladen statt Sackgassen-Alert)
- Offline-UX: OfflineBanner ist da — aber jede schreibende Aktion muss offline klar sagen was passiert (Queue vs. blockiert)
- Haptik (`UIImpactFeedbackGenerator`) auf Bezahlen-Erfolg, Session-Schluss, Storno — Kassenkräfte schauen nicht auf den Screen
- Dynamic Type bis XXL testen (Zahlen dürfen nie truncaten — Geldbetrag „1.234…" ist ein Bug), VoiceOver-Labels auf allen Geld-Werten
- Landscape + Split View (iPad-Realität: nebenbei WhatsApp)
- Touch-Targets ≥44pt nachmessen (v3 behauptet es — verifizieren), Tap-Feedback <100ms
- Session-Ablauf (16h-Limit): forceLogout-Banner darf keinen Warenkorb verlieren — Zustand sichern

**Pro Screen (Auszug der bekannten Schwächen):**
- OrderView: Warenkorb-Performance bei 50+ Positionen (List statt VStack?), Produkt-Grid-Suche fehlt
- PaymentView: Rückgeld groß und zuerst (das liest der Kellner), Gemischt-Eingabe mit Live-Validierung statt stummem Button-Disable
- TableOverview: Pull-to-Refresh + Auto-Refresh-Intervall (Stale-Daten nach App-Wechsel)
- ZBericht/Berichte: Zahlen-Alignment (monospacedDigit konsequent), Differenz-Farblogik (rot erst ab Schwelle, nicht bei ±1 Cent)
- Onboarding: Wiedereinstieg bei Abbruch auf Schritt 4 (State-Persistenz)

---

## 7. Tests & Qualität

| # | Lücke | Inhalt | Prio |
|---|---|---|---|
| T1 | **Backend-Unit-Tests: nur 1 Datei** (vatCalculation) | Unit-Tests für: Split-Partition-Validierung, Storno-Negations-Invariante (SUM==0), Z-Bericht-Aggregation (Fixture-basiert), sequences (Mock-Conn), Fiskaly-Payload-Bau (amounts_per_vat_rate-Format, centsToFiskaly) | Vor Go-live |
| T2 | **iOS: null Tests** | XCTest-Target: parseCents/euroString (Rundung, Locale), buildPayments (Gemischt-Kanten: bar==total, bar>total), VatBreakdown-Berechnung vs. Backend-Formel, Store-Decoding gegen Response-Fixtures | Vor Go-live |
| T3 | **E2E-Durchstich** | Ein Integrationstest über den ganzen Tag: Session auf → 3 Orders (bar/karte/gemischt/split) → Storno → Movements → Session zu → Z-Bericht-Invarianten (expected_cash, Summen netten, Bon-Nummern lückenlos) | Vor Go-live |
| T4 | **Nebenläufigkeits-Tests** | `Promise.all`-Doppel-Requests gegen pay/cancel/close — jetzt wo die Locks da sind, absichern dass sie bleiben | Nach Pilot |
| T5 | **CI** | GitHub Actions: tsc + unit + integration (MariaDB-Service-Container) als PR-Gate; iOS-Build via xcodebuild | Mit N5 |
| T6 | **Backend: `any` eliminieren (237 Stellen, davon 160 `db.execute<any[]>`)** | Request-Seite ist via Zod schon typisiert (`z.infer`), die DB-Seite nicht. Plan: (1) Row-Interfaces pro Tabelle in `src/db/types.ts` (`OrderRow`, `ReceiptRow`, …) und `db.execute<OrderRow[]>` — Achtung: mysql2-Generics sind reine Casts, keine Runtime-Prüfung, daher Spalten-Drift weiter durch Integrationstests absichern; (2) `ResultSetHeader` statt `<any>` für INSERT/UPDATE-Ergebnisse; (3) `catch (err: unknown)` + Narrowing statt `err: any`; (4) ESLint `@typescript-eslint/no-explicit-any: error` als Ratchet, Geld-Pfade zuerst (payments, splitBill, cancellations, sessions). iOS ist sauber (nur KeychainHelper nutzt `[String: Any]` — Security-C-API, unvermeidbar) | Vor Go-live, schrittweise |

---

## 8. Stabilität / Performance / Robustheit

| # | Punkt | Warum | Prio |
|---|---|---|---|
| S1 | **Error-Monitoring (Sentry)** | Bugs blockieren direkt Einnahmen des Kunden; stdout-Logs liest niemand. `@sentry/node` + captureException im Error-Handler, ~20 min | Vor Go-live |
| S2 | **Rate-Limit: in-memory Store** | Reset bei Restart, nicht Cluster-fähig (PM2), per-IP statt per-Tenant (NAT-Problem) → Redis-Store + keyGenerator nach tenantMiddleware | Vor Multi-Instanz |
| S3 | **subscriptionMiddleware: DB-Query pro Request** | Status in JWT-Claim, DB nur bei `trial` | Nach Pilot |
| S4 | **A5: Report-Queries nicht index-fähig** | s. Audit | Nach Pilot |
| S5 | **Docker Compose** | Onboarding zweiter Entwickler / neues Gerät | Gelegenheit |
| S6 | **DB-Pool-Sizing + Timeouts prüfen** | Session-Locks serialisieren Zahlungen pro Gerät — bei Multi-Tenant-Last Pool-Größe & `innodb_lock_wait_timeout` bewusst setzen | Vor Go-live |

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

1. **Jetzt (Pilot läuft an):** A4 (Zahlungs-Retry-UX) → T2-Grundstock (Geld-Funktionen) → Pilot-Feedback-Schleife
2. **Vor Go-live (Reihenfolge):** B1 E-Mail → B2 Cron → B3 Passwort-Reset → B6/B7 Prozess-Härtung → B4/B5 → A3/A6/A9 → T1/T3 → S1/S6 → N1–N9 parallel (Rechtliches/Fiskaly/ELSTER haben Vorlauf!)
3. **Phase 2 (TSE scharf):** A1 + A2 lösen → Fiskaly-Sandbox-E2E → N2/N3
4. **Nach Pilot:** §6 impeccable-Pass komplett, T4/T5, S2–S4
5. **Phase 3+:** Trinkgeld (nach Steuerberater), SyncManager-Vollausbau, Phase-5-Features

---

*Pflege: Nach jeder Änderung erledigte Punkte hier streichen (CLAUDE.md-Regel). Neue Erkenntnisse mit Prio + Warum eintragen — nicht nur Was.*

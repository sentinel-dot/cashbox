# Betrieb — Monitoring, Prozess-Lebenszyklus, E-Mail und Hintergrund-Jobs

Stand: 2026-07-22 (ROADMAP S03/S06/S07/S08/S09). Betrifft Monitoring, Shutdown,
Resend-Betrieb, die zeitgesteuerten Jobs (§5), den Passwort-Reset (§6) und die
DB-Berechtigungen in Produktion (§7).

---

## 1. Error-Monitoring (Sentry)

### Warum
stdout-Logs liest im Pilotbetrieb niemand. Ein 500er beim Bezahlen blockiert direkt den
Umsatz des Wirts — wir müssen davon erfahren, bevor er anruft.

### Konfiguration

| Variable | Wirkung |
|---|---|
| `SENTRY_DSN` | Leer ⇒ Sentry ist **komplett aus**, alle `captureException`-Aufrufe sind No-Ops. So laufen Dev und Tests ohne Sonderbehandlung. |
| `NODE_ENV` | Wird als Sentry-`environment` gesetzt (`production` / `development`). |

### Was gemeldet wird — und was nicht

Gemeldet werden **nur 5xx** aus dem globalen Error-Handler (`app.ts`) sowie
`unhandledRejection` / `uncaughtException` / Startup-Fehler (`index.ts`).
4xx gehen bewusst **nicht** an Sentry: falscher PIN, 409 auf geschlossene Session und
422-Validierungsfehler sind Normalbetrieb und würden das Monitoring zurauschen.

Mitgesendet wird ausschließlich, was `captureException()` explizit als Tag übergibt:

- `tenant` (aus dem JWT, nie aus Body/Params — wie überall sonst)
- `method`, `url`, `source`

**Nicht** gesendet werden Request-Bodies, Header, Cookies, IP-Adressen, Namen, Bons oder
Beträge (`sendDefaultPii: false`, kein Express-Request-Handler, kein Performance-Tracing).
Das ist für die AVV mit Sentry relevant (OFFEN.md N8) und **muss so bleiben** — wer den
Kontext erweitert, prüft vorher, ob das Feld personenbezogen ist.

### Nachweis (TC-M zu REQ-OPS-002)

Der Transportpfad wurde am 2026-07-19 gegen einen lokalen Ingest-Endpoint verifiziert
(DSN auf `http://…@localhost:9999/1`), um die Kette ohne echtes Sentry-Konto zu prüfen:

```
>>> EMPFANGEN auf /api/1/envelope/?sentry_version=7&sentry_key=publickey&sentry_client=sentry.javascript.node/10.66.0
    Exception: Error: S03 Test-Event — Sentry-Verdrahtung
    Tags:  {"tenant":"42","method":"POST","source":"S03-Verifikation"}
    Extra: {"url":"/orders/7/pay"}
    Environment: production
```

Damit ist belegt: Init, Tag-Serialisierung (`tenant` als String), Envelope-Aufbau,
HTTP-Transport und `flush()` funktionieren. Die *Verdrahtung* im Error-Handler ist
dauerhaft durch `integration/errorHandler.test.ts` abgesichert.

**Offen (User):** Sentry-Projekt anlegen, echten DSN in die Prod-`.env` eintragen und
einmal ein Test-Event im Dashboard sichten. Alerting-Regel setzen (mind.: jede neue
Fehler-Signatur → Mail).

---

## 2. Kontrolliertes Herunterfahren

### Warum
Ein `kill` mitten in `payOrder` bricht die DB-Transaktion ab, während die Bon-Nummer aus
`receipt_sequences` unter Umständen schon gezogen ist. Laufende Requests müssen deshalb
zu Ende laufen, bevor der Prozess geht.

### Ablauf

Signale: `SIGTERM` (Deploy via PM2/systemd), `SIGINT` (Ctrl-C lokal).
Zusätzlich lösen `unhandledRejection` und `uncaughtException` denselben Pfad mit Exit-Code 1
aus — Node würde sonst hart crashen, ohne Drain und ohne Sentry-Meldung.

```
Signal
 └─ 1. Cron-Jobs stoppen     (S07; kein Job startet mehr in das Herunterfahren hinein)
    2. HTTP-Server drainen   (closeIdleConnections() + close(); laufende Requests laufen aus)
    3. Sentry flushen        (sonst geht genau der Fehler verloren, der uns beendet hat)
    4. DB-Pools schließen    (db, auditDb, readonlyDb — allSettled)
    5. process.exit(code)
```

Ein Job, der beim Signal schon läuft, wird nicht abgewartet — alle Jobs sind idempotent
und laufen nach dem Neustart erneut (siehe §5).

Die Reihenfolge ist die eigentliche Zusage und in `unit/shutdown.test.ts` festgenagelt.
Ein zweites Signal während des Drains wird ignoriert (Idempotenz) — sonst würden die Pools
doppelt geschlossen.

**Notbremse:** Kommt der Drain nicht innerhalb von 10 s durch, beendet sich der Prozess
selbst mit Exit-Code 1. Ohne sie würde ihn der Prozess-Manager später mit `SIGKILL`
treffen — garantiert unkontrolliert.

`closeIdleConnections()` ist nicht optional: iPads halten Keep-Alive-Verbindungen offen,
auf denen gerade kein Request läuft. Ohne den Aufruf kehrt `server.close()` nicht zurück
und jeder Deploy liefe in die 10-s-Notbremse.

### Nachweis (TC-M zu REQ-OPS-001)

Verifiziert am 2026-07-19 gegen `node dist/index.js` (NODE_ENV=test, Port 3999):

**a) SIGTERM im Leerlauf** — sauberer Drain, Exit-Code 0:

```
INFO: Shutdown eingeleitet                                reason: "SIGTERM"  timeoutMs: 10000
INFO: HTTP-Server gedrained — keine offenen Requests mehr  reason: "SIGTERM"
INFO: DB-Pools geschlossen                                 reason: "SIGTERM"
INFO: Shutdown abgeschlossen                               reason: "SIGTERM"  exitCode: 0
```

**b) SIGTERM bei offener Keep-Alive-Verbindung** — Shutdown-Dauer **42 ms**
(Notbremse liegt bei 10 000 ms). Belegt, dass `closeIdleConnections()` greift; ohne den
Aufruf wäre hier der Timeout-Pfad gelaufen.

### Für den Prozess-Manager (relevant ab S20)

PM2/systemd müssen dem Prozess nach `SIGTERM` mindestens 15 s Zeit lassen (10 s Notbremse
+ Reserve), bevor sie `SIGKILL` schicken — sonst ist die ganze Mechanik wirkungslos:

- PM2: `kill_timeout: 15000`
- systemd: `TimeoutStopSec=15`

---

## 3. Bekannte Einschränkung

`npm run dev` (`ts-node src/index.ts`) startet **nicht**: ts-node löst im CommonJS-Modus die
`.js`-Endungen der relativen Imports nicht auf `.ts` auf (`Cannot find module './sentry.js'`).
Das betrifft jeden Import in `index.ts` und ist unabhängig von S03 — Tests laufen über
vitest, Produktion über `npm run build` + `npm start`. Notiert in OFFEN.md (T8).

---

## 4. Transaktionsmails mit Resend

### Sicherheitszustand und Variablen

Ohne `RESEND_API_KEY` arbeitet der Mail-Service absichtlich im Dry-Run: Er rendert und
protokolliert den Vorgang, sendet aber nichts nach außen. Das bleibt für Development und CI
der Standard. Produktionswerte gehören ausschließlich in den Secret Store bzw. die nicht
committete Produktions-`.env`:

| Variable | Produktionswert |
|---|---|
| `RESEND_API_KEY` | API-Key des cashbox-Resend-Projekts |
| `MAIL_FROM` | `cashbox <noreply@mail.<hauptdomain>>` |
| `APP_URL` | Öffentliche Basis-URL für Abo-, Export-, Reset- und Berichtslinks |

API-Key, Reset-Token und reale Empfängeradressen dürfen weder in Git noch in Nachweisprotokolle.
Der periodische Queue-Drain läuft seit S07 alle 5 Minuten (§5); für die einmalige Abnahme
lässt er sich mit `npm run job -- email-drain` sofort auslösen.

### Domain, SPF und DKIM

Die Hauptdomain ist noch nicht ausgewählt. Sobald sie vorhanden ist, wird eine dedizierte
Versand-Subdomain `mail.<hauptdomain>` verwendet. Das isoliert die Versand-Reputation vom
restlichen Domainverkehr und entspricht der Resend-Empfehlung.

1. Im Resend-Dashboard unter **Domains → Add Domain** `mail.<hauptdomain>` hinzufügen.
2. Sämtliche dort angezeigten SPF-, DKIM- und Return-Path-DNS-Einträge beim DNS-Provider
   **wortgetreu** anlegen. Record-Typ, Host und Wert nicht aus Beispielen dieser Doku ableiten:
   Resend erzeugt sie für die konkrete Domain.
3. Existiert am exakt selben Host bereits ein SPF-TXT-Record, keinen zweiten `v=spf1`-Record
   danebenlegen. Die autorisierten Quellen in einem einzigen SPF-Record zusammenführen oder
   vorab klären, ob Resends separate Return-Path-Subdomain den Konflikt vermeidet.
4. DNS-Propagation abwarten und in Resend **Verify DNS Records** auslösen. Erst der Status
   `verified` belegt, dass SPF und DKIM für den Versand erkannt wurden.

Aktuelle Referenz: [Resend — Managing Domains](https://resend.com/docs/dashboard/domains/introduction).

### DMARC stufenweise aktivieren

DMARC kommt nach erfolgreicher SPF-/DKIM-Verifikation als TXT-Record an
`_dmarc.mail.<hauptdomain>` hinzu. Die Reporting-Adresse muss real existieren und regelmäßig
ausgewertet werden.

1. Monitoring starten: `v=DMARC1; p=none; rua=mailto:dmarc-reports@<hauptdomain>;`
2. Aus cashbox und allen anderen legitimen Absendern Testmails senden. In den vollständigen
   Headern `spf=pass`, `dkim=pass` und `dmarc=pass` prüfen; Reports mindestens mehrere Tage
   auf unbekannte Quellen kontrollieren.
3. Erst danach auf `p=quarantine` und schließlich `p=reject` verschärfen. Nie direkt mit
   `reject` starten, solange nicht alle legitimen Absender inventarisiert sind.

Aktuelle Referenz: [Resend — Implementing DMARC](https://resend.com/docs/dashboard/domains/dmarc).

### Abnahmeprotokoll (REQ-MAIL-011)

S06 ist extern erst abgenommen, wenn alle Punkte belegt sind:

- [ ] Resend-Domainstatus `verified`
- [ ] `MAIL_FROM`, `APP_URL` und `RESEND_API_KEY` sicher in der Produktionsumgebung gesetzt
- [ ] Repräsentative Mail an die eigene Adresse zugestellt; HTML und Plaintext geprüft
- [ ] Header zeigen `spf=pass`, `dkim=pass` und `dmarc=pass`
- [ ] Resend-Message-ID stimmt mit `email_log.provider_message_id` überein
- [ ] Datum und anonymisierte Nachweis-ID hier ergänzt: **offen — Domain noch nicht vorhanden**

---

## 5. Hintergrund-Jobs (Cron)

### Warum im selben Prozess

`src/cron.ts` läuft neben dem API-Server (`startCron()` in `index.ts`), nicht als eigener
Dienst. Ein zweiter Prozess wäre vor allem eine weitere Sache, die man beim Deploy zu
starten vergessen kann — und laut S20 fährt PM2 ohnehin eine einzelne Instanz. Für den
Fall, dass daraus später mehrere werden, ist der Schutz trotzdem eingebaut: jeder Job
claimt seine Zeilen atomar und dedupliziert über einen Marker in der DB, ein Doppellauf
erzeugt also keine zweite Mail und keinen zweiten Z-Bericht. `CRON_ENABLED=false` schaltet
einzelne Instanzen zusätzlich stumm.

Zeitzone aller Zeitpläne: **Europe/Berlin** — „täglich 6 Uhr" heißt Ortszeit des Wirts,
auch wenn der Server auf UTC läuft.

### Was läuft wann

| Job | Zeitplan | Aufgabe | Idempotenz-Marker |
|-----|----------|---------|-------------------|
| `email-drain` | alle 5 min | Fällige Mails versenden, Backoff, `email_log`-Nachweis | `email_queue.status` + `idempotency_key` |
| `long-open-sessions` | stündlich :10 | Sitzung > 24 h offen → Owner-Mail (GoBD) | Mail-Key `long_open_session:<tenant>:<session>:24h` |
| `tse-outage-report` | stündlich :15 | TSE-Ausfall > 48 h → Owner-Mail (KassenSichV) | `tse_outages.notified_at` |
| `offline-queue-drain` | stündlich :20 | Offene Offline-Bons serverseitig nachsignieren | atomarer Claim (`processing_started_at`) |
| `offline-queue-alerts` | stündlich :25 | Endgültig gescheiterte Einträge melden | `offline_queue.alerted_at` |
| `z-report-backfill` | stündlich :30 | Fehlende Z-Berichte nachtragen (A9) | Existenz der `z_reports`-Zeile + UNIQUE(session_id) |
| `trial-warnings` | täglich 06:00 | Trial-Warnung Tag 10 + 13 | Mail-Key `trial_warning:<tenant>:day10\|day13` |
| `subscription-grace` | täglich 06:15 | Abgelaufene Kulanzfrist melden | Mail-Key `subscription_event:<tenant>:grace_expired:<periodEnd>` |

Die stündlichen Jobs liegen bewusst auf verschiedenen Minuten: alle gleichzeitig hieße,
dass fünf Jobs mit dem laufenden Kassenbetrieb um dieselben Zeilen konkurrieren.

**Abweichung von der ROADMAP-Planung:** „Sitzung > 24 h" und „TSE-Ausfall > 48 h" waren dort
als Tagesjobs geplant und laufen stündlich. Beide Mails gehen pro Vorfall genau einmal raus,
es entsteht also kein Spam — aber eine Meldepflicht bis zu 24 h liegen zu lassen, wäre bei
einem TSE-Ausfall nicht vertretbar.

### Was der `subscription-grace`-Job bewusst NICHT tut

Er ändert `subscription_status` nicht. Gesperrt wird weiterhin bei jedem Request in der
`subscriptionMiddleware` (402 nach Ablauf der Kulanzfrist), die dieselben Fristen aus
`services/subscription.ts` liest. Würde der Cron zusätzlich auf `cancelled` schreiben,
wäre Stripe nicht mehr die alleinige Quelle des Abo-Status und der Wirt läse „Abonnement
gekündigt", wo nur eine Zahlung fehlgeschlagen ist. Der Job macht das Ereignis sichtbar:
Mail, `audit_log`, Sentry. Abgelöst wird das von der Entitlement-Matrix in S17C.

### Einen Job von Hand auslösen

```bash
npm run job -- --list              # alle Jobs mit Zeitplan und Zweck
npm run job -- z-report-backfill   # genau diesen Job jetzt laufen lassen
```

Das ist nach einem Vorfall der normale Weg — auf die nächste volle Stunde zu warten, hilft
niemandem. Alle Jobs sind idempotent, ein manueller Lauf neben dem Zeitplan ist ungefährlich.

### Wenn ein Alert kommt

- **„Offline-Queue-Eintrag endgültig fehlgeschlagen"** — ein Bon hat keine TSE-Signatur und
  bekommt sie nicht mehr von allein. `offline_queue.error_message` lesen; typisch sind
  Fiskaly-4xx (Konfiguration) oder ein Eintrag ohne `receipt_id` (Zahlung nie abgeschlossen).
  Nach der Ursachenbehebung: Zeile wieder auf `pending` setzen und `offline-queue-drain`
  von Hand starten.
- **„Z-Bericht fehlte und wurde nachgetragen"** — der Bericht ist da, aber der `z_reports`-
  INSERT beim Schließen ist gescheitert (Grants von `audit_insert_user`? DB weg?). Der
  Snapshot trägt `reconstructed: true` und ist damit auch für einen Prüfer nachvollziehbar.
  Die Ursache gehört trotzdem angesehen.
- **„TSE-Ausfall länger als 48 h"** — jetzt ist die Meldung ans Finanzamt über ELSTER fällig
  (`tse_outages.reported_to_finanzamt` anschließend manuell setzen).
- **„Kulanzfrist abgelaufen"** — der Zugriff ist gesperrt; der Wirt braucht eine gültige
  Zahlungsmethode oder ein neues Abo.

---

## 6. Passwort-Reset (S08)

### Warum das Backend eine HTML-Seite ausliefert

Die App ist iPad-only, ein Web-Frontend gibt es nicht. Der Link aus der
Reset-Mail muss trotzdem überall funktionieren — typischerweise öffnet der Wirt
ihn auf dem Handy, während das iPad an der Theke steht. Deshalb rendert das
Backend die Reset-Seite selbst: eine Datei (`src/views/passwordResetPage.ts`),
Inline-CSS, **kein JavaScript**, kein externer Request. Das ist bewusst der
einzige HTML-Endpunkt des Systems; alles andere bleibt JSON-API.

### Pflicht-Variable

`PUBLIC_API_URL` muss auf die von außen per HTTPS erreichbare Basis-URL **dieses
Backends** zeigen (nicht auf `APP_URL`). Fehlt sie, baut der Server Links auf den
Default `https://api.cashbox.de` — und jeder Reset-Link läuft ins Leere, ohne
dass es jemandem auffällt, bis der erste Wirt anruft. Nach dem Deploy einmal
prüfen: Reset für ein Testkonto anfordern und den Link im Mailtext ansehen.

### Ablauf und Fristen

1. `POST /auth/forgot-password` (App) → Token wird ausgestellt, Mail eingereiht.
2. Versand über den `email-drain`-Job (alle 5 min) — **eine Reset-Mail kann also
   bis zu fünf Minuten brauchen.** Das ist der Preis der Queue und für diesen
   Anlass vertretbar; wer schneller muss: `npm run job -- email-drain`.
3. Link ist **1 Stunde** gültig und **einmal** einlösbar. Ein neu angeforderter
   Link entwertet den vorherigen.
4. Nach dem Reset sind alle vorher begonnenen Sitzungen ungültig
   (`users.password_changed_at`) — betroffene iPads zeigen das
   „Sitzung abgelaufen"-Banner und verlangen eine Neuanmeldung.

### Grenzen, die absichtlich so sind

- Der Endpunkt antwortet **immer** 200, auch bei unbekannter Adresse. Ein Wirt,
  der sich vertippt, bekommt deshalb keine Fehlermeldung, sondern nie eine Mail.
  Bei Supportfällen zuerst die Schreibweise der Adresse in `users` prüfen.
- Pro Nutzer gehen höchstens **3 Reset-Mails pro Stunde** raus (Schutz fremder
  Postfächer). Weitere Anfragen werden still verworfen — sichtbar nur im Log
  (`Passwort-Reset gedrosselt`).
- Der Klartext-Token steht ausschließlich in der Mail: nicht in der DB (nur
  SHA-256), nicht in `email_queue`-Schlüsseln und nicht in Logs (`redactUrl` in
  `src/logger.ts` entfernt die Query dieser Route). **Wer eine neue Route mit
  Geheimnis in der URL baut, trägt sie dort ein.**

### Wenn ein Nutzer nicht mehr reinkommt

`SELECT id, expires_at, used_at FROM password_reset_tokens WHERE user_id = ?`
zeigt, ob überhaupt ein Token ausgestellt wurde. Kein Eintrag ⇒ die Anfrage kam
nie an oder die Adresse/das Gerät passte nicht. Eintrag vorhanden, aber
`used_at` gesetzt ⇒ der Link wurde schon benutzt (oder durch einen neueren
entwertet) — neu anfordern lassen.

---

## 7. DB-Berechtigungen in Produktion (S09 / Audit A6)

### Warum drei User

`app_user` schreibt den Alltagsbetrieb, `audit_insert_user` ausschließlich die
append-only-Tabellen, `app_readonly` liest für Berichte. Der Sinn des zweiten
Users ist, dass er **nichts anderes kann**: GoBD-Zeilen sollen sich nicht
überschreiben lassen, und zwar erzwungen von der Datenbank, nicht nur vom Code.
Ein pauschales `GRANT INSERT ON cashbox.*` hätte diesen Schutz aufgehoben —
damit hätte derselbe Account auch `orders`, `payments` oder `users` befüllen
können.

### Soll-Zustand

`scripts/setup-db.ts` setzt ihn für Dev und Test automatisch (Liste
`AUDIT_INSERT_TABLES`). In Produktion läuft das Script **nicht** — dort legt der
DBA die User an, mit exakt diesen Grants:

```sql
-- append-only: nur INSERT, nur diese sechs Tabellen
GRANT INSERT ON cashbox.audit_log             TO 'audit_insert_user'@'<host>';
GRANT INSERT ON cashbox.z_reports             TO 'audit_insert_user'@'<host>';
GRANT INSERT ON cashbox.product_price_history TO 'audit_insert_user'@'<host>';
GRANT INSERT ON cashbox.order_item_modifiers  TO 'audit_insert_user'@'<host>';
GRANT INSERT ON cashbox.order_item_removals   TO 'audit_insert_user'@'<host>';
GRANT INSERT ON cashbox.email_log             TO 'audit_insert_user'@'<host>';

-- Bestands-DB: ein früher vergebenes datenbankweites INSERT muss weg.
-- Grants sind additiv — ohne REVOKE bleibt es neben den Tabellen-Grants stehen.
REVOKE INSERT ON cashbox.* FROM 'audit_insert_user'@'<host>';

FLUSH PRIVILEGES;
```

Prüfen:

```sql
SHOW GRANTS FOR 'audit_insert_user'@'<host>';
```

Erwartet: `USAGE ON *.*` plus genau sechs `INSERT ON cashbox.<tabelle>`-Zeilen.
Taucht dort `INSERT ON cashbox.*` auf, ist der REVOKE nicht gelaufen.

### Wenn eine neue Audit-Tabelle dazukommt

Drei Stellen, sonst scheitert der INSERT erst zur Laufzeit in Produktion:

1. `AUDIT_INSERT_TABLES` in `scripts/setup-db.ts`
2. die Liste in `src/__tests__/integration/db-grants.test.ts` (bewusst eine
   zweite, unabhängige Aufschreibung — sie muss angefasst werden, wenn jemand
   die Grants aufweicht)
3. dieser Abschnitt + „DB-Berechtigungen" in `CLAUDE.md`, und der DBA vergibt
   den Grant auf der Prod-DB nach.

### Symptom bei fehlendem Grant

`ER_TABLEACCESS_DENIED_ERROR` aus einem `auditDb.execute` — im Log als 500 mit
Sentry-Event. Betroffen sind je nach Tabelle: Audit-Log (jede schreibende
Aktion), Z-Bericht beim Schichtende (Backfill-Job springt ein, §5),
Preishistorie und Preset-Import, Modifier beim Bestellen (Position wird
kompensiert, siehe unten) sowie der Versandnachweis der Mail-Queue.

### Modifier-Kompensation in `addItem` (A3)

`order_item_modifiers` schreibt der Audit-User **nach** dem Commit der Position
— zwei DB-User können keine gemeinsame Transaktion haben. Scheitert der INSERT,
markiert der Controller die Position unter dem Order-Lock über
`order_item_removals` als entfernt (GoBD: kein DELETE) und antwortet 500. Für
den Betrieb heißt das: die Kasse zeigt „bitte erneut hinzufügen", der Retry
erzeugt **kein** Duplikat, und in der DB steht eine Position mit dem Grund
`Systemfehler: Modifier konnten nicht gespeichert werden`. Häufen sich diese
Einträge, ist die Ursache fast immer der Audit-Grant oder der DB-Pool — nicht
das Kassenpersonal.

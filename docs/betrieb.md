# Betrieb — Monitoring & Prozess-Lebenszyklus

Stand: 2026-07-19 (ROADMAP S03). Betrifft `src/sentry.ts`, `src/shutdown.ts`, `src/index.ts`.

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
 └─ 1. HTTP-Server drainen   (closeIdleConnections() + close(); laufende Requests laufen aus)
    2. Sentry flushen        (sonst geht genau der Fehler verloren, der uns beendet hat)
    3. DB-Pools schließen    (db, auditDb, readonlyDb — allSettled)
    4. process.exit(code)
```

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

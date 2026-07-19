# CI — GitHub Actions als PR-Gate

Stand: 2026-07-19 (Paket S01 aus `ROADMAP.md`)

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

## Was läuft

Job **`backend`** auf `ubuntu-latest`, bei jedem Push auf `main` und jedem PR gegen `main`:

| Schritt | Kommando | Warum |
|---|---|---|
| Timezone-Tabellen | `mariadb-tzinfo-to-sql` im Service-Container | Berichte nutzen `CONVERT_TZ` (s.u.) |
| Guard | `SELECT CONVERT_TZ(NOW(), '+00:00', 'Europe/Berlin')` | Bricht ab, wenn der vorige Schritt still gescheitert ist |
| Install | `npm ci` | Lockfile-treu |
| Typecheck | `npx tsc --noEmit` | |
| Test-DB | `npm run db:setup:test` | Legt DB + 3 User + Grants an, fährt Migrations hoch |
| Unit + Compliance | `npm test` | |
| Integration | `npm run test:integration` | Gegen echte MariaDB |

**Nicht** im Gate: `npm run test:external` (Fiskaly-Sandbox + Stripe) — braucht echte Credentials und
läuft nightly bzw. manuell. `npm run test:coverage` ebenfalls nicht (kein Erkenntnisgewinn pro PR).

Job **`ios`** auf `macos-26` (Paket S02), parallel zum Backend-Job:

| Schritt | Was |
|---|---|
| iPad-Simulator wählen | neueste iOS-Runtime, darin das erste iPad; UDID via `GITHUB_OUTPUT` |
| XCTest-Suite | `xcodebuild test -scheme zettel-frontend -destination "…,id=<UDID>" CODE_SIGNING_ALLOWED=NO` |
| Result-Bundle | nur bei Fehlschlag als Artefakt `xcresult` (7 Tage) |

Drei Punkte dazu:

- **Geteiltes Scheme ist Pflicht.** `xcuserdata/` ist gitignored — ohne
  `xcshareddata/xcschemes/zettel-frontend.xcscheme` im Repo findet `xcodebuild` das Scheme auf dem
  Runner nicht. Wer ein neues Scheme anlegt: in Xcode „Shared" anhaken und committen.
- **Keine feste Destination.** Die Simulator-Ausstattung unterscheidet sich je Runner-Image, deshalb
  wird sie zur Laufzeit per `simctl … --json` + `jq` ermittelt. Ein fest verdrahtetes
  `name=iPad Pro 11-inch (M5)` würde beim nächsten Image-Update brechen.
- **`macos-26`, nicht `macos-latest`.** Das Test-Target hat `IPHONEOS_DEPLOYMENT_TARGET = 26.2` und
  braucht damit Xcode 26 + iOS-26.2-Runtime; `macos-latest` zeigt derzeit auf macOS 15 mit Xcode 16
  und würde scheitern. Das Image ist bei GitHub noch **Preview** — bewusst akzeptiert. Die saubere
  Alternative (Test-Target auf 18.2 senken, App-Mindestversion) hängt an `OFFEN.md` T7.
- **Kein Signing.** `CODE_SIGNING_ALLOWED=NO` — Simulator-Tests brauchen keine Zertifikate, damit
  auch keine Apple-Secrets in CI. Erst der TestFlight-Build (S04) braucht das.

## Keine Repo-Secrets nötig

`backend/.env.test` ist bewusst committet und enthält ausschließlich Wegwerf-Credentials
(`test_password`, ein fixes Test-JWT-Secret). Es gibt darin nichts, was in Produktion gilt.
Der Backend-Job kommt deshalb ohne GitHub-Secrets aus.

⚠️ Wenn dort je ein echtes Secret landen soll: **nicht** in `.env.test` — dann Repo-Secret anlegen
und im Workflow via `env:` durchreichen.

## Drei Stolpersteine, die im Workflow gelöst sind

### 1. Grant-Host (`DB_USER_HOST`)

`backend/scripts/setup-db.ts` legte die DB-User früher fest als `'app_user_test'@'localhost'` an.
In CI läuft MariaDB als Service-Container; Verbindungen kommen über die Docker-Bridge an, MariaDB
sieht also die Gateway-IP statt `localhost` → Grants greifen nicht, alles scheitert mit
*Access denied*.

Das Script liest jetzt `DB_USER_HOST` (Default `localhost`, lokal also unverändert). Der Workflow
setzt `DB_USER_HOST: '%'`. Bewusst so gelöst, statt die Grant-Logik in der CI zu duplizieren —
sonst driften CI-Rechte und `npm run db:setup` auseinander, und genau diese Grants sind der
GoBD-Schutz gegen DELETE auf Finanztabellen (siehe CLAUDE.md).

### 2. Timezone-Tabellen

`reportsController.ts` und `receiptsController.ts` ordnen Geschäftstage per
`CONVERT_TZ(…, '+00:00', 'Europe/Berlin')` zu. Ohne geladene Timezone-Tabellen liefert MariaDB
`NULL` — die Tests würden dann nicht krachen, sondern still 0 Umsatz messen. Deshalb lädt der
Workflow die Tabellen und **verifiziert** danach mit einem eigenen Schritt, dass `CONVERT_TZ`
nicht `NULL` liefert.

Dieselbe Voraussetzung gilt in Produktion (CLAUDE.md → Betriebshinweis).

### 3. Port-Mapping statt Container-Job

`backend/src/__tests__/setup.ts` lädt `.env.test` mit `override: true` — im Testlauf gelten also
zwingend `DB_HOST=localhost` und `DB_PORT=3306` aus der Datei, exportierte Env-Variablen verlieren.
Der Service-Container muss deshalb `3306:3306` auf den Runner mappen; ein Container-Job, der die DB
unter dem Service-Hostname `mariadb` erreicht, würde nicht funktionieren.

`setup-db.ts`, `migrate.ts` und `db/index.ts` laden dotenv **ohne** `override` — dort gewinnen die
Workflow-Variablen (`DB_ADMIN_PASSWORD`, `DB_USER_HOST`) wie erwartet.

## Branch Protection

Der Workflow allein blockt nichts — scharf wird das Gate durch die Branch-Protection-Regel auf `main`:

```bash
gh api -X PUT repos/sentinel-dot/cashbox/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Backend (tsc + unit + integration)"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
JSON
```

Aktiv seit 2026-07-19. Folge: **Änderungen an `main` laufen über PRs**, Force-Pushes und Löschen
des Branches sind gesperrt, und ein PR ist erst mergebar, wenn der Check grün **und** der Branch
aktuell ist (`strict: true`).

`enforce_admins` steht bewusst auf `false`: als Repo-Admin kommst du im Notfall (kaputter Runner,
GitHub-Ausfall) noch an `main` — die Regel ist ein Gate, kein Selbstfesseln. Wer sie nutzt, sollte
das im Commit begründen.

Bei S02 muss der iOS-Check hier in `contexts` ergänzt werden.

## Lokal reproduzieren

Der CI-Lauf ist identisch zu:

```bash
cd backend
npx tsc --noEmit
npm run db:setup:test
npm test
npm run test:integration
```

Wenn Report-Tests lokal 0 liefern, fehlen die Timezone-Tabellen auch lokal:

```bash
mariadb-tzinfo-to-sql /usr/share/zoneinfo | mariadb -u root mysql
```

iOS-Job lokal:

```bash
cd zettel-frontend
xcodebuild test -project zettel-frontend.xcodeproj -scheme zettel-frontend \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  CODE_SIGNING_ALLOWED=NO
```

## Nachweis „roter Test → roter PR" (DoD S01)

Durchgeführt am 2026-07-19 auf PR [#1](https://github.com/sentinel-dot/cashbox/pull/1)
(Branch `ci/s01-github-actions`):

**1. Roter Lauf** — Run `29702114397`. Ein Assert in `unit/vatCalculation.test.ts` wurde absichtlich
auf `expect(netCents).toBe(999)` gesetzt (korrekt sind 1000 bei `calcVat(1190, '19')`).

| Schritt | Ergebnis |
|---|---|
| tzinfo laden + verifizieren | ✅ |
| Typecheck | ✅ |
| Test-DB aufsetzen (`db:setup:test` mit `DB_USER_HOST=%`) | ✅ |
| Unit- + Compliance-Tests | ❌ `AssertionError: expected 1000 to be 999` |
| Integrationstests | übersprungen |

Check-Status `failure` → PR nicht mergebar. Die Schritte davor bestätigen zugleich, dass
Grant-Host und Timezone-Tabellen in CI korrekt greifen.

**2. Grüner Lauf** — Run `29702157037`, nach Rücknahme des Asserts: alle Schritte ✅,
**76 Unit/Compliance (7 Dateien) + 301 Integration (22 Dateien)** — identisch zum lokalen Lauf.
Laufzeit der Integrationstests in CI: ~39 s.

## Nachweis iOS-Job (DoD S02)

Durchgeführt am 2026-07-19 auf PR [#2](https://github.com/sentinel-dot/cashbox/pull/2):

**Grüner Lauf** — Run `29702799713`: Simulator automatisch gewählt
(`iPad Pro 13-inch (M5)`), `** TEST SUCCEEDED **`, 40 Testfälle.

**Roter Lauf** — Run `29703020329`: `EuroStringTests.testStandardBetrag` erwartete absichtlich
`"12,51 €"` → `Test case 'EuroStringTests.testStandardBetrag()' failed`, `** TEST FAILED **`,
Check `iOS (xcodebuild test)` rot — **während der Backend-Job im selben Lauf grün blieb**. Damit ist
belegt, dass die beiden Jobs unabhängig voneinander greifen.

Nebenbefund dabei: Die Doku sprach von 41 XCTests, tatsächlich sind es **40** (8+5+12+7+8
Testmethoden). In `CLAUDE.md`, `OFFEN.md` und `ROADMAP.md` korrigiert.

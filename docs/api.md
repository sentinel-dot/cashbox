# API-Referenz (Auszug)

Diese Datei dokumentiert Endpunkt-Verträge, die über das hinausgehen, was
`CLAUDE.md` (Implementierungsstand) als Einzeiler führt. Aktuell: der
Products-/Sortiment-Bereich inkl. Starter-Presets (S17A/S17B). Andere Domänen
folgen bei Bedarf.

Alle Routen laufen hinter `authMiddleware → deviceMiddleware → tenantMiddleware
→ subscriptionMiddleware`; `tenant_id` kommt ausschließlich aus dem JWT.
Geldbeträge sind immer Integer-Cent.

---

## Produkte

### GET /products

Kassen- und Management-Abfrage in einem Endpoint.

| Query-Param | Werte | Bedeutung |
|---|---|---|
| `include_inactive` | `0` (Default) / `1` | `1` = Management-Ansicht inkl. deaktivierter Produkte. Ohne Param sieht die Kasse ausschließlich aktive Produkte. |

Unbekannte Query-Params → **400** (strict).

Sortierung (deterministisch, iOS spiegelt sie in `assortmentSorted`):
`(Kategorie IS NULL), Kategorie-sort_order, Kategorie-Name, Produkt-sort_order, Produkt-Name, Produkt-ID`.

Response-Zeile enthält u.a. `sort_order`, `visual_key` (String|null) und
`category { id, name, color, sort_order }`.

### POST /products  (owner/manager, Plan-Limit)

Body: `name`, `price_cents`, `vat_rate_inhouse` (`'7'|'19'`), optional
`vat_rate_takeaway`, `category_id`, `sort_order`, `visual_key` (Whitelist, s.u.).
Ohne `sort_order`: Append ans Kategorie-Ende (`MAX+10`).

**GoBD-Härtung (S17B):** läuft über `services/products.ts →
createProductWithHistory`: Produkt wird **inaktiv** angelegt, dann der initiale
`product_price_history`-Eintrag geschrieben (auditDb, INSERT-only), dessen Werte
verifiziert, erst danach aktiviert. Ein aktives Produkt ohne Preis-Historie ist
damit unmöglich; ein Fehlschlag hinterlässt höchstens einen inaktiven Rest.

### PATCH /products/:id  (owner/manager)

Nur `name`, `category_id`, `is_active`, `visual_key`. Preis-/Steuerfelder → 400
(GoBD; Preisänderung ausschließlich über `POST /products/:id/price`).

### PATCH /products/reorder  (owner/manager)

```json
{ "category_id": 3 | null, "product_ids": [12, 5, 9] }
```

Komplette geordnete ID-Liste eines Kategorie-Scopes; `sort_order` wird als
`(index+1)*10` in einer Transaktion gesetzt. Jede ID muss dem Tenant gehören
UND im angegebenen Scope liegen, sonst **404** ohne Änderung. Idempotent.

### PATCH /products/categories/reorder  (owner/manager)

```json
{ "category_ids": [7, 2, 4] }
```

Analog für Kategorien (nur aktive).

---

## Starter-Sortimente (S17B)

Verbindliche Fachspezifikation: `docs/s17-sortiment-starterpakete.md`.

### GET /products/presets  (alle Rollen)

Liefert die vier versionierten Presets (`shisha_bar@1`, `cafe@1`, `spaeti@1`,
`empty@1`) mit Kategorien (Farbrolle zu HEX aufgelöst) und Produktzeilen:
`item_key`, `name_de`, `sort_order`, `vat_rate_*`, `vat_review`
(`standard_19 | food_7_2026 | recipe_review | printed_price_review`),
`visual_key`, `deposit_cents` (0|25), `requires_custom_name`,
`requires_exact_price`. `price_cents` ist immer `null` — Presets enthalten
keine Produktionspreise.

### POST /products/presets/import  (owner/manager)

Header: `Idempotency-Key: <UUID>` — **Pflicht**; Retry/Doppeltap muss denselben
Key senden.

```json
{
  "preset_id": "cafe",
  "preset_version": 1,
  "tax_basis_version": "de-ust-2026-01",
  "vat_confirmed": true,
  "items": [
    {
      "item_key": "espresso",
      "name": "Espresso",
      "price_cents": 280,
      "vat_rate_inhouse": "19",
      "vat_rate_takeaway": "19",
      "visual_key": "espresso",
      "review_confirmed": true,
      "on_name_collision": "skip"
    }
  ]
}
```

Serverseitige Re-Validierung gegen die eigene Preset-Definition (Client-Zeilen
wird nicht vertraut):

| Regel | Fehler |
|---|---|
| Unbekannter/doppelter `item_key`, falsche Version | 400 |
| `deposit_cents == 25` (Pfand-Release-Gate, §5.4) | 400 `code: deposit_gate` |
| `standard_19`/`food_7_2026`: Satz weicht vom Vorschlag ab | 400 |
| `recipe_review`/`printed_price_review` ohne `review_confirmed: true` | 400 `code: review_required` |
| Tabakvorlage ohne konkreten eigenen Namen | 400 `code: custom_name_required` |
| Plan-Limit: aktive Produkte + Import > Limit (Bulk-Prüfung) | 403 |
| Fehlender/ungültiger Idempotency-Key | 400 |
| Zod-Verstöße (Float-Preis, 0-Preis, `vat_confirmed != true`, visual_key nicht in Whitelist) | 422 |

Idempotenz (Tabelle `preset_imports`, UNIQUE `(tenant_id, idempotency_key)`):

- Key unbekannt → Import läuft, Ergebnis wird gespeichert → **201**
- Key bekannt + `completed` → **200** mit gespeichertem Ergebnis (Replay)
- Key bekannt + `processing` (< 2 min) → **409** „Import läuft bereits"
- Key bekannt + `failed`/stale `processing` → atomare Übernahme + erneuter Lauf

Produkte laufen über `createProductWithHistory` mit Herkunft
(`origin_preset_id/-version/-item_key`, UNIQUE je Tenant): Wiederholungen
duplizieren nichts, halbe Importe werden repariert, vom Betreiber deaktivierte
Import-Produkte werden **nie** still reaktiviert. Namensgleichheit mit manuell
angelegten Produkten: `on_name_collision` `skip` (Default) oder `create`.

Response **201**:

```json
{
  "import_id": 7,
  "imported": { "categories": 4, "products": 21 },
  "skipped": [ { "item_key": "cola", "reason": "name_collision" } ]
}
```

`reason` ∈ `name_collision | already_imported`. Der komplette bestätigte
Snapshot (inkl. `tax_basis_version`) landet als `preset.imported` im Audit-Log.

### visual_key-Whitelist

39 semantische Schlüssel (`backend/src/services/presets/presetTypes.ts`,
Spec §6.2). Die DB speichert nie SF-Symbol-Namen; `null` = Textkachel.
Unbekannte Werte rendert iOS defensiv als `generic`.

---

## Passwort-Reset (S08)

Drei Routen, alle **ohne** `authMiddleware` (wer sein Passwort vergessen hat,
hat kein Token). Rate-Limit auf allen dreien; zusätzlich greift ein Limit pro
Nutzer und Stunde (`services/passwordReset.ts`).

### POST /auth/forgot-password

Body: `email`, `device_token`. Der Tenant kommt wie beim Login aus dem
registrierten Gerät — `users.email` ist nur je Tenant eindeutig.

Antwortet **immer** `200 {"ok": true}`. Unbekannte Adresse, gesperrtes Gerät,
deaktivierter Nutzer und Drosselung sind von außen nicht unterscheidbar; sonst
wäre der Endpunkt ein Verzeichnis aller Konten eines Betriebs. Einzige
Ausnahme: 422 bei Schema-Verstoß (fehlende Felder).

### GET /auth/reset-password?token=…

Liefert **HTML**, nicht JSON — der einzige HTML-Endpunkt des Backends. Grund:
Der Link aus der Mail muss auf jedem Gerät funktionieren, ein Web-Frontend gibt
es nicht. Die Seite ist selbsttragend (Inline-CSS, **kein JavaScript** — helmets
CSP erlaubt keine Inline-Skripte), `noindex`, `Cache-Control: no-store`,
`Referrer-Policy: no-referrer`.

Der Aufruf prüft den Token **nicht** gegen die DB und verbraucht ihn nicht.

### POST /auth/reset-password

Formular-Submit der Seite oben — `application/x-www-form-urlencoded`
(`token`, `new_password`, `new_password_repeat`), Antwort ist wieder HTML.
Validierung per `safeParse` im Controller statt `validationMiddleware`, weil
dessen 422-JSON der Nutzer im Browser roh sähe.

| Fall | Status | Antwort |
|---|---|---|
| Erfolg | 200 | Bestätigungsseite („jetzt am iPad anmelden") |
| Passwort < 8 Zeichen / Wiederholung abweichend | 422 | Formular erneut, mit Meldung — Token bleibt gültig |
| Token unbekannt / abgelaufen / verbraucht / Nutzer inaktiv | 400 | Fehlerseite mit Grund im Klartext |

**Token-Regeln:** 32 Byte Zufall (base64url), in der DB nur `SHA2(…,256)`,
eine Stunde gültig, genau einmal einlösbar; ein neu angeforderter Link entwertet
den vorherigen. Zwei gleichzeitige Submits desselben Links werden über
`FOR UPDATE` serialisiert — genau einer gewinnt.

**Sitzungen:** Ein erfolgreicher Reset setzt `users.password_changed_at`.
`POST /auth/refresh` gibt danach 401 für jedes Refresh-Token, dessen
`session_start` davor liegt — ein gestohlenes Token überlebt den Reset nicht.

**Betrieb:** `PUBLIC_API_URL` muss auf die von außen per HTTPS erreichbare
Basis-URL dieses Backends zeigen, sonst läuft jeder Reset-Link ins Leere.

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

Erstelle eine neue API-Route für das Kassensystem. Ich gebe dir den Routennamen und die Methode, du scaffoldest alles vollständig.

**Was du erstellst:**

1. **Route-Datei** (`src/routes/<name>.ts`) mit:
   - Express Router
   - Middleware-Reihenfolge (per Route): `authMiddleware → deviceMiddleware → tenantMiddleware → subscriptionMiddleware → [sessionMiddleware wenn Order/Payment] → planMiddleware → validationMiddleware(schema) → handler`
   - Hinweis: `rateLimitMiddleware` ist global in `app.ts` registriert — **nicht** pro Route hinzufügen

2. **Zod-Schema** für jeden Request-Body (inline in der Route-Datei oder in `src/schemas/<name>.ts`)
   - Geldbeträge als `z.number().int().nonnegative()` (Cent, niemals Float)
   - Enums als `z.enum([...])` mit Whitelist
   - **Query-Params (GET-Routen):** `validationMiddleware` validiert nur `req.body` — Query-Params via `schema.safeParse(req.query)` direkt im Controller validieren, **nicht** via `validationMiddleware`

3. **Controller** (`src/controllers/<name>.ts`) mit:
   - `tenant_id` aus `req.auth!.tenantId` (nie aus Body/Params)
   - Alle DB-Queries mit `WHERE tenant_id = ?`
   - Finanzoperationen (Receipts, Payments): `SELECT ... FOR UPDATE` für Sequenzen
   - Audit-Log-Eintrag wenn Finanzdaten betroffen

4. **Test-Datei** (`src/__tests__/integration/<name>.test.ts`) mit:
   - Happy Path Test
   - Tenant-Isolation Test: Tenant B kann nicht auf Daten von Tenant A zugreifen (404 oder 403)
   - Validierungsfehler Test: fehlende Pflichtfelder → 422

**Kritische Regeln (nie vergessen):**
- KEIN DELETE/UPDATE auf: orders, order_items, receipts, payments, cancellations, audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals
- Order-Item entfernen → `INSERT INTO order_item_removals`, nicht `DELETE FROM order_items`
- Preisänderung → `POST /products/:id/price` via `product_price_history`, nicht `UPDATE products SET price_cents`
- Geldbeträge immer Integer (Cent)
- tenant_id IMMER aus JWT

**Format der Eingabe:** Beschreibe die Route kurz, z.B.:
"POST /orders/:id/items — fügt ein Produkt zur Bestellung hinzu, mit optionalen Modifiers"

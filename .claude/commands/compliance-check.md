Prüfe den angegebenen Code auf GoBD- und KassenSichV-Konformität für das Kassensystem.

**Prüfe folgende Punkte und berichte für jeden explizit (✅ OK / ❌ Problem / ⚠️ Warnung):**

### Finanzdaten-Integrität (GoBD)
- [ ] Gibt es DELETE-Statements auf Finanztabellen? (orders, order_items, receipts, payments, cancellations, audit_log, z_reports, product_price_history, order_item_modifiers, order_item_removals)
- [ ] Wird `order_item_removals` für das Entfernen von Positionen genutzt (INSERT, nie DELETE auf order_items)?
- [ ] Gibt es UPDATE-Statements auf diesen Tabellen?
- [ ] Werden Preisänderungen korrekt über `product_price_history` statt `UPDATE products SET price_cents` gemacht?
- [ ] Werden Stornos als Gegenbuchung (neuer Receipt + cancellations-Eintrag) umgesetzt?

### Bon-Nummern (GoBD)
- [ ] Wird `receipt_number` ausschließlich über `receipt_sequences` mit `SELECT ... FOR UPDATE` vergeben?
- [ ] Werden Nummern-Lücken (bei TX-Fehlern) als `status='voided'` dokumentiert?

### Bon-Pflichtfelder (KassenSichV)
- [ ] Enthält der generierte Bon: Unternehmensname, Adresse, Steuernummer/USt-IdNr.?
- [ ] Sind TSE-Felder vorhanden: `tse_serial_number`, `tse_signature`, `tse_counter`, `tse_transaction_start`, `tse_transaction_end`?
- [ ] Ist `device_id` und `device_name` im Receipt gespeichert? (§6 Abs.1 Nr.6 KassenSichV)
- [ ] Ist der QR-Code mit TSE-Daten generiert?

### Tenant-Isolation
- [ ] Enthalten ALLE DB-Queries `WHERE tenant_id = ?`?
- [ ] Kommt `tenant_id` ausschließlich aus `req.auth!.tenantId` (JWT), nie aus Body/Params?
- [ ] Werden Modifier-Option-IDs auf Zugehörigkeit zum Tenant geprüft?

### Geldbeträge
- [ ] Sind alle Geldbeträge Integer (Cent)? Kein Float, kein Decimal?
- [ ] Ist die subtotal-Formel korrekt: `(product_price_cents + SUM(modifier_delta_cents)) × quantity - discount_cents`?
- [ ] Werden Beträge an Fiskaly korrekt als Strings mit 2 Dezimalstellen übergeben?

### Validierung
- [ ] Hat jede Route ein Zod-Schema?
- [ ] Wird `validationMiddleware` verwendet?
- [ ] Sind Enum-Felder als Whitelist validiert?

### TSE / Fiskaly
- [ ] Hat jede TSE-Operation einen `idempotency_key`?
- [ ] Gibt es einen Recovery-Pfad bei Timeout (GET /tx/{id} prüfen)?
- [ ] Wird `client_id = device.tse_client_id` übergeben?

### Deaktivierte Features
- [ ] Ist Trinkgeld-Logic implementiert? (Erst ab Phase 3 erlaubt)
- [ ] Ist Außer-Haus-Toggle implementiert? (Erst ab Phase 4 erlaubt)

### Offene Infrastruktur-Punkte (Phase 3+)
- [ ] Ist `versionMiddleware` implementiert? (API-Version-Header + Deprecation-Warnings für iOS-App-Updates)
- [ ] Gibt es Cron-Jobs für: Trial-Ablauf-Warnung (Tag 10+13), `past_due`-Sperrung, TSE-Ausfall-ELSTER-Frist?
- [ ] Gibt es einen E-Mail-Service für: Trial-Ablauf, Passwort-Reset, Subscription-Events?
- [ ] Gibt es einen Passwort-Reset-Flow (`POST /auth/forgot-password`, `POST /auth/reset-password`)?

**Am Ende:** Gesamtbewertung und Liste der Punkte die vor einem Merge behoben werden müssen.

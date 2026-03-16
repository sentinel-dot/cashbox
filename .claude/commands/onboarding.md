Scaffolde oder erweitere den Onboarding-Flow für neue Tenants im Kassensystem.

**Was der Onboarding-Flow abdeckt:**

### Schritt 1: Tenant registrieren (`POST /onboarding/register`)
Erstellt Tenant + Admin-User atomisch in einer Transaktion:
- Tenant anlegen (`tenants`-Tabelle): Name, Slug, `subscription_status = 'trial'`
- Admin-User anlegen (`users`-Tabelle): Rolle `owner`, bcrypt-Hash
- `receipt_sequences`-Eintrag anlegen (Startwert 1)
- JWT zurückgeben (kein separater Login-Step nötig)

Zod-Schema:
```typescript
z.object({
  business_name: z.string().min(2).max(100),
  email: z.string().email(),
  password: z.string().min(8),
  // Für Bon-Pflichtfelder (KassenSichV):
  address: z.string().min(5),
  tax_number: z.string().min(5),  // Steuernummer oder USt-IdNr.
})
```

### Schritt 2: Erstes Gerät registrieren (`POST /devices` — existiert bereits)
- Nach Register sofort Gerät anlegen
- `tse_client_id` bei Fiskaly registrieren (TSE-Client anlegen) — **NUR in Phase 2**
- In Phase 1: `tse_client_id = NULL`, kein Fiskaly-Aufruf

### Schritt 3: Stripe Checkout (`POST /onboarding/create-checkout-session`)
- Stripe Customer anlegen (`stripe.customers.create`)
- `stripe_customer_id` in `tenants` speichern
- Checkout-Session mit Plan-Preis-ID zurückgeben
- Nach `checkout.session.completed`-Webhook: `subscription_status = 'active'`

### Trial-Logik
- `subscription_status = 'trial'` erlaubt vollen Zugang für 14 Tage
- `subscriptionMiddleware` prüft: `trial` oder `active` → OK; `past_due` → 402; `cancelled` → 403

### Fiskaly TSS-Erstellung (Phase 2 — noch nicht aktiv)
Bei Registrierung muss in Phase 2 zusätzlich eine TSS angelegt werden:
```typescript
// Phase 2 only — in Phase 1 weglassen, tenants.fiskaly_tss_id bleibt NULL
const tss = await fiskaly.post('/tss', { ... })
await fiskaly.put(`/tss/${tss.id}`, { state: 'INITIALIZED' })
await db.query('UPDATE tenants SET fiskaly_tss_id = ? WHERE id = ?', [tss.id, tenantId])
```

### ELSTER / Finanzamt-Meldung — wichtig zu verstehen
ELSTER ist **keine API** die cashbox direkt aufruft. ELSTER ist das Finanzamt-Portal:
- **Neue Kasse melden** (einmalig, manuell): Tenant meldet neue TSS im ELSTER-Portal an — cashbox zeigt Checkliste im Onboarding-Wizard, aber kein API-Call
- **TSE-Ausfall >48h melden** (KassenSichV-Pflicht): cashbox trackt in `tse_outages`, sendet E-Mail an Owner — Owner meldet Ausfall beim Finanzamt (teils ELSTER, teils Brief, je Bundesland)
- **⚠️ Cron-Job für Ausfall-Prüfung noch nicht implementiert** — `tse_outages`-Tabelle vorhanden, aber automatische 48h-Prüfung fehlt

### Kritische Regeln
- Tenant-Anlage + User-Anlage in **einer DB-Transaktion** — kein Partial-State
- `tenant_id` im JWT wird nach Register sofort gesetzt
- Kein `authMiddleware` auf `POST /onboarding/register` (User existiert noch nicht)
- Stripe-Keys aus Env — nie aus Request-Body

**Format der Eingabe:** Beschreibe welchen Teil du implementieren willst, z.B.:
"POST /onboarding/register — Tenant + Admin-User anlegen"
"POST /onboarding/create-checkout-session — Stripe Checkout starten"

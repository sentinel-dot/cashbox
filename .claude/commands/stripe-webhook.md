Implementiere oder erweitere Stripe-Webhook-Handling für das Kassensystem.

**Was du erstellst / prüfst:**

### Webhook-Endpunkt (`POST /webhooks/stripe`)
- Signatur-Verifikation via `stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET)`
- **rawBody** muss als Buffer ankommen — `express.raw({ type: 'application/json' })` **vor** `express.json()` registrieren
- Kein `authMiddleware` auf diesem Endpunkt (Stripe authentifiziert via Signatur)

### Events die behandelt werden müssen
| Event | Aktion |
|-------|--------|
| `customer.subscription.created` | `tenants.subscription_status = 'active'`, Plan setzen |
| `customer.subscription.updated` | Plan-Wechsel in `tenants` updaten |
| `customer.subscription.deleted` | `subscription_status = 'cancelled'`, Zugang sperren |
| `invoice.payment_succeeded` | `subscription_current_period_end` updaten |
| `invoice.payment_failed` | `subscription_status = 'past_due'`, Benachrichtigung |
| `checkout.session.completed` | Onboarding abschließen (initial Setup) |

### Idempotenz
- Stripe kann Events mehrfach senden — `stripe_event_id` in separater Tabelle speichern oder prüfen
- Bei Duplikat: HTTP 200 zurückgeben (Stripe braucht 200, sonst Retry-Loop)

### Kritische Regeln
- STRIPE_WEBHOOK_SECRET aus Env — nie hardcoden
- Webhook muss **immer** HTTP 200 zurückgeben wenn Signatur valid (auch bei unbekannten Events)
- `tenant_id` aus `stripe_customer_id` auflösen — nie aus Request-Body übernehmen
- Alle DB-Änderungen in Transaktion (subscription update + audit_log)

**Format der Eingabe:** Beschreibe welchen Webhook-Event du implementieren willst, z.B.:
"subscription.deleted — Tenant sperren wenn Abo endet"
"checkout.session.completed — Onboarding-Flow abschließen"

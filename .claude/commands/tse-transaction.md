Scaffolde eine vollständige Fiskaly TSE-Transaktions-Methode für das Kassensystem.

**Was du erstellst:**

Eine vollständige Service-Methode in `src/services/fiskaly.ts` mit:

### 1. Haupt-Flow (3-stufig, alle via PUT mit ?tx_revision=N)
```
PUT /tss/{tss_id}/tx/{id}?tx_revision=1  → TX starten (state: ACTIVE, client_id)
PUT /tss/{tss_id}/tx/{id}?tx_revision=2  → TX befüllen (amounts_per_vat_rate, amounts_per_payment_type + schema)
PUT /tss/{tss_id}/tx/{id}?tx_revision=3  → TX abschließen (state: FINISHED, volles Schema wiederholen!) → Signatur, Counter, Timestamps
```

### 2. Pflichtfelder im Request (ACHTUNG: Singular, kein trailing 's')
- `client_id`: immer `device.tse_client_id` (nie TSS-ID verwenden)
- `amounts_per_vat_rate`: NORMAL (19%), REDUCED_1 (7%) — nur wenn Betrag > 0
  - Jeder Eintrag braucht `amount` (Brutto, **required**) + optional `excl_vat_amounts: { amount, vat_amount }`
- `amounts_per_payment_type`: CASH und/oder NON_CASH — Beträge als String ("30.50"), nicht Cent-Integer
- **WICHTIG**: Das vollständige Schema (`amounts_per_vat_rate` + `amounts_per_payment_type`) muss bei JEDEM PUT mitgeschickt werden — auch beim FINISHED-Request
- Bei Storno: `receipt_type: "CANCELLATION"`

### 3. Idempotenz bei Timeout (kritisch!)
```typescript
// Vor finish-Request: prüfen ob TX bereits abgeschlossen
const existing = await getFiskalyTx(tss_id, tx_id)
if (existing.state === 'FINISHED') {
  return mapFiskalyResponse(existing) // vorhandene Signatur verwenden, kein neuer Request
}
```

### 4. Offline-Fallback
- Wenn Fiskaly nicht erreichbar: `offline_queue`-Eintrag mit `idempotency_key` anlegen
- Receipt mit `tse_pending = TRUE` erstellen
- Bon-Vermerk: "TSE-Signatur ausstehend"
- Audit-Log-Eintrag mit Timestamp der verzögerten Signierung

### 5. Error Handling
- Netzwerkfehler → Offline-Fallback
- 409 Conflict (bereits abgeschlossen) → Idempotenz-Pfad
- 4xx Validierungsfehler → nicht retryable, sofort fehlschlagen + voided receipt
- 5xx Serverfehler → retry mit exponential backoff (max 3 Versuche), dann Offline-Fallback

### 6. Rückgabe (wird in receipts gespeichert)
```typescript
{
  tse_transaction_id: string
  tse_serial_number: string
  tse_signature: string
  tse_counter: number
  tse_transaction_start: Date
  tse_transaction_end: Date
}
```

### Kritische Regeln
- Geldbeträge an Fiskaly: immer Strings mit 2 Dezimalstellen ("30.50") — NICHT Cent-Integer
- `idempotency_key` muss mit dem TSE-Request gespeichert und bei Recovery geprüft werden
- Jede TSE-Operation in `audit_log` dokumentieren

**Format der Eingabe:** Beschreibe den Zahlungsfall, z.B.:
"Einfache Barzahlung 33,50€ (7% und 19% MwSt gemischt)"
"Gemischte Zahlung: 10€ Bar + 20€ Karte"
"Storno von Receipt #42"

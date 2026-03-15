Scaffolde die Bon-Generierungslogik für das Kassensystem (digitaler Bon — kein Drucker).

**Was du erstellst:**

### 1. Receipt-Service (`src/services/receipts.ts`)
Methode die aus DB-Daten ein vollständiges Receipt-Objekt baut und alle Pflichtfelder prüft.

### 2. Pflichtfeld-Checkliste (KassenSichV + GoBD + §14 UStG)
Der generierte Bon MUSS alle diese Felder enthalten und befüllt haben:

| Feld | Quelle | Gesetz |
|------|--------|--------|
| Unternehmensname | `tenants.name` | §14 UStG |
| Vollständige Adresse | `tenants.address` | §14 UStG |
| Steuernummer oder USt-IdNr. | `tenants.tax_number` / `tenants.vat_id` | §14 UStG |
| Bon-Nummer (fortlaufend) | `receipts.receipt_number` | KassenSichV |
| Datum + Uhrzeit | `receipts.created_at` | KassenSichV |
| TX-Beginn | `receipts.tse_transaction_start` | KassenSichV |
| TX-Ende | `receipts.tse_transaction_end` | KassenSichV |
| Kassensystem-Bezeichnung + ID | `receipts.device_name` + `receipts.device_id` | §6 Abs.1 Nr.6 KassenSichV |
| Positionen: Name, Menge, Einzelpreis, Gesamt | `order_items` Snapshot | §14 UStG |
| Modifier pro Position (wenn vorhanden) | `order_item_modifiers` Snapshot | GoBD |
| MwSt-Aufschlüsselung 7% + 19% getrennt | `receipts.vat_*` | §14 UStG |
| Zahlungsart(en) | `payments.method` | KassenSichV |
| TSE-Seriennummer | `receipts.tse_serial_number` | KassenSichV |
| TSE-Signatur | `receipts.tse_signature` | KassenSichV |
| TX-Counter | `receipts.tse_counter` | KassenSichV |
| QR-Code (TSE-Daten kodiert) | generiert aus TSE-Feldern | BSI TR-03153 |
| Bei Storno: Original-Bon-Nummer lesbar | `cancellations.original_receipt_number` | GoBD |
| Bei Rabatt: Betrag + Grund | `order_items.discount_*` | GoBD |
| Bei Außer-Haus: Vermerk (Phase 4+) | `receipts.is_takeaway` | UStG |

### 3. Validierungsfunktion (für Tests)
```typescript
function validateReceiptFields(receipt: ReceiptData): ValidationResult {
  // Prüft alle Pflichtfelder
  // Gibt Liste fehlender Felder zurück
  // Wird in receipt-compliance.test.ts verwendet
}
```

### 4. SwiftUI ReceiptView
- Alle Pflichtfelder sichtbar angezeigt
- Modifier als Unterzeilen pro Position (+Aufpreis)
- QR-Code generiert und sichtbar
- "TSE-Signatur ausstehend" Hinweis wenn `tse_pending = TRUE`
- "PDF senden" Button (E-Mail oder Teilen)
- Bei Offline-Bon: deutlicher Hinweis, kein QR-Code

### 5. Offline-Bon-Sonderfall
Wenn `tse_pending = TRUE`:
- Bon anzeigen ohne TSE-Felder
- Deutlicher Hinweis: "TSE-Signatur ausstehend — Bon wird nach Verbindungsherstellung aktualisiert"
- Kein QR-Code (TSE-Daten fehlen)
- Bon darf dem Kunden gezeigt werden, aber rechtlich unvollständig bis Signierung

### 6. Betragsberechnung (zur Kontrolle)
```
Netto 7%  + MwSt 7%  + Netto 19% + MwSt 19% = total_gross_cents
SUM(order_items.subtotal_cents) = total_gross_cents  (nach Rabatten, inkl. Modifier)
```

**Format der Eingabe:** Beschreibe den Bon-Typ, z.B.:
"Standard-Bon: Barzahlung, gemischte MwSt, mit Modifiers"
"Storno-Bon: Referenz auf Original-Bon #42"
"Split-Bon: Person 2 von 4, nur ausgewählte Positionen"
"Offline-Bon: TSE-Signatur noch ausstehend"

Erstelle eine neue Datenbank-Migration für das Kassensystem (MariaDB).

**Was du erstellst:**

Eine Migration-Datei unter `src/db/migrations/<timestamp>_<beschreibung>.ts` mit:

```typescript
export async function up(db: Connection): Promise<void> {
  // Migration hier
}

export async function down(db: Connection): Promise<void> {
  // Rollback hier — muss die up()-Änderungen vollständig rückgängig machen
}
```

**Pflichtkommentare in der Migration:**
- Bei Finanztabellen: `-- GoBD: NUR INSERT, kein UPDATE/DELETE`
- Bei neuen Spalten auf Finanztabellen: `-- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt`
- Bei receipt_number-bezogenen Änderungen: `-- KassenSichV: fortlaufend, niemals zurücksetzen`

**GoBD-Regeln für Migrationen:**
- NIEMALS Spalten löschen aus: orders, order_items, receipts, payments, cancellations, audit_log, z_reports
- NIEMALS Daten aus Finanztabellen löschen (kein DELETE in up() auf Finanzdaten)
- Neue NOT NULL Spalten auf bestehenden Tabellen brauchen DEFAULT oder Migrations-Datenbefüllung
- Rollback (down()) darf bei Finanztabellen NUR Spalten entfernen die in up() hinzugefügt wurden — keine Datenlöschung

**DB-Berechtigungen beachten:**
- `audit_log`, `z_reports`, `product_price_history`, `order_item_modifiers`: INSERT-only User
- Neue Tabellen dieser Art: in Kommentar dokumentieren welcher DB-User Zugriff bekommt

**Format der Eingabe:** Beschreibe was geändert werden soll, z.B.:
"Füge `note VARCHAR(255) NULL` zu `order_items` hinzu für Sonderwunsch-Kommentare"

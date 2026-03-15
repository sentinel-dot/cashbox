Generiere GoBD-konforme Testdaten für die cashbox_test-Datenbank.

**Verwende dieses etablierte Setup-Pattern** (aus den Integration-Tests):

```typescript
async function setup(conn: any, plan = 'business') {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Test GmbH', 'Teststr. 1, 10115 Berlin', ?, 'active')`,
    [plan]
  );
  const tenantId = t.insertId as number;

  // receipt_sequences MUSS für jeden Tenant existieren
  await conn.execute(
    'INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)',
    [tenantId]
  );

  const hash = await bcrypt.hash('password', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Owner', 'owner@test.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('device-token').digest('hex');
  const [d] = await conn.execute(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad', ?)`,
    [tenantId, tokenHash]
  );
  const deviceId = d.insertId as number;

  const token = jwt.sign(
    { userId, tenantId, deviceId, role: 'owner' } as AuthPayload,
    process.env['JWT_SECRET'] ?? 'test-secret',
    { expiresIn: '15m' }
  );
  return { tenantId, userId, deviceId, token };
}
```

**GoBD-Regeln für Seed-Daten:**
- Preise **nie** direkt in `products.price_cents` setzen — stattdessen `product_price_history`-Eintrag anlegen
- `receipt_number` immer über `receipt_sequences` (SELECT ... FOR UPDATE), nie manuell setzen
- Snapshots in `order_items` (product_name, price_cents zum Bestellzeitpunkt) korrekt befüllen
- Modifier-Snapshots in `order_item_modifiers` (name, delta_cents zum Bestellzeitpunkt)
- Offene Kassensitzung für Orders/Payments: `INSERT INTO cash_register_sessions (tenant_id, device_id, opened_by, status)`

**Tenant-Isolation bei Seed:**
- Jeder Test-Tenant bekommt seine eigenen Daten — nie tenant_id mischen
- Für Isolation-Tests: zweiten Tenant anlegen (ebenfalls mit receipt_sequences)

**Cleanup:**
- `cleanTestDB()` aus `src/__tests__/testHelpers.ts` löscht alle Tabellen in FK-sicherer Reihenfolge
- Wird automatisch via `afterEach` in `src/__tests__/setup.ts` aufgerufen — kein manuelles Cleanup nötig

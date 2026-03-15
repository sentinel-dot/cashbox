Scaffolde eine Integrations-Testdatei für das Kassensystem.

Ich gebe dir den zu testenden Endpoint, du erstellst eine vollständige Testdatei.

**Erstelle `src/__tests__/integration/<name>.test.ts` mit diesem Grundgerüst:**

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';
import type { AuthPayload } from '../../middleware/authMiddleware.js';

// ─── Setup ────────────────────────────────────────────────────────────────────

async function setup(conn: any, plan = 'business') {
  const [t] = await conn.execute(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES ('Test GmbH', 'Teststr. 1, 10115 Berlin', ?, 'active')`,
    [plan]
  );
  const tenantId = t.insertId as number;
  await conn.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [tenantId]);

  const hash = await bcrypt.hash('pw', 10);
  const [u] = await conn.execute(
    `INSERT INTO users (tenant_id, name, email, password_hash, role)
     VALUES (?, 'Owner', 'o@t.de', ?, 'owner')`,
    [tenantId, hash]
  );
  const userId = u.insertId as number;

  const tokenHash = crypto.createHash('sha256').update('tok').digest('hex');
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

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('METHOD /route', () => {
  let token: string;
  let tenantId: number;

  beforeEach(async () => {
    ({ token, tenantId } = await setup(db));
  });
  afterEach(() => { /* cleanup: global afterEach in setup.ts */ });

  it('Happy Path: ...', async () => {
    const res = await request(app)
      .post('/route')
      .set('Authorization', `Bearer ${token}`)
      .send({ /* valid body */ });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
  });

  it('Tenant-Isolation: Tenant B kann nicht auf Daten von Tenant A zugreifen', async () => {
    // Ressource für Tenant A anlegen
    const [row] = await db.execute(`INSERT INTO ... (tenant_id, ...) VALUES (?, ...)`, [tenantId, ...]) as any;
    const resourceId = row.insertId;

    // Tenant B aufbauen
    const { token: tokenB } = await setup(db, 'business');

    // Tenant B versucht Tenant-A-Ressource zu lesen → 404
    const res = await request(app)
      .get(`/route/${resourceId}`)
      .set('Authorization', `Bearer ${tokenB}`);
    expect(res.status).toBe(404);
  });

  it('Validierungsfehler: fehlende Pflichtfelder → 422', async () => {
    const res = await request(app)
      .post('/route')
      .set('Authorization', `Bearer ${token}`)
      .send({}); // body leer
    expect(res.status).toBe(422);
  });

  it('Unautorisiert: kein Token → 401', async () => {
    const res = await request(app).post('/route').send({ /* valid body */ });
    expect(res.status).toBe(401);
  });
});
```

**Pflicht-Tests für jeden Endpoint:**
1. Happy Path (korrekte Eingabe → erwartetes Ergebnis)
2. Tenant-Isolation (andere Tenant sieht/verändert keine fremden Daten → 404)
3. Validierungsfehler (fehlende/ungültige Felder → 422)
4. Unautorisiert (kein JWT → 401)

**Weitere Tests je nach Endpoint:**
- GoBD-Immutabilität: `price_cents` via PATCH → 400 mit `hint`
- Plan-Limit: zu viele Ressourcen für Plan → 403
- Kassensitzungspflicht: kein offenes `cash_register_session` → 409

**Wichtige Hinweise:**
- `afterEach` kommentieren: cleanup läuft global via `setup.ts` — kein eigenes `cleanTestDB()` nötig
- Zweiter Tenant für Isolation braucht ebenfalls `receipt_sequences`-Eintrag
- `token` enthält `{ userId, tenantId, deviceId, role }` als `AuthPayload`
- Für Plan-Limit-Tests: separaten `describe`-Block mit eigenem `beforeEach` und `plan = 'starter'`
- `vitest.config.ts` hat `fileParallelism: false` — Test-Dateien laufen sequentiell (shared DB)

**Format der Eingabe:**
Beschreibe den Endpoint kurz, z.B.:
"GET /products/:id — gibt ein einzelnes Produkt zurück, nur wenn es zum eigenen Tenant gehört"

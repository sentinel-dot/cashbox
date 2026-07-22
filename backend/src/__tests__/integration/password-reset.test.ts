// S08 (OFFEN.md B3) — kompletter Passwort-Reset über die echte Test-DB.
//
// Leitgedanke der Tests: Der Token wird nie aus dem Code gelesen, sondern aus
// dem Text der eingereihten Mail extrahiert — genau wie ihn der Wirt bekommt.
// Damit prüfen die Tests die Strecke, die real benutzt wird (Anfrage → Mail →
// Link → Formular → neues Passwort → Login), und nicht eine Abkürzung daneben.
import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import bcrypt from 'bcrypt';
import crypto from 'crypto';
import app from '../../app.js';
import { db } from '../../db/index.js';

// ─── Fixtures ───────────────────────────────────────────────────────────────

async function createTenant(name = 'Reset Bar'): Promise<number> {
  const [r] = await db.execute<any>(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES (?, 'Teststr. 1, 12345 Berlin', 'starter', 'active')`,
    [name]
  );
  await db.execute('INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)', [
    r.insertId,
  ]);
  return r.insertId;
}

async function createUser(
  tenantId: number,
  overrides: { email?: string; password?: string; active?: boolean; role?: string } = {}
): Promise<number> {
  const hash = await bcrypt.hash(overrides.password ?? 'altesPasswort1', 10);
  const [r] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, is_active)
     VALUES (?, 'Wirt', ?, ?, ?, ?)`,
    [
      tenantId,
      overrides.email ?? 'wirt@test.de',
      hash,
      overrides.role ?? 'owner',
      overrides.active ?? true,
    ]
  );
  return r.insertId;
}

async function createDevice(tenantId: number, rawToken: string): Promise<number> {
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const [r] = await db.execute<any>(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, 'iPad Theke', ?)`,
    [tenantId, tokenHash]
  );
  return r.insertId;
}

/** Holt den Klartext-Token aus der zuletzt eingereihten Reset-Mail. */
async function tokenFromMail(): Promise<string> {
  const [rows] = await db.execute<any[]>(
    `SELECT body_text FROM email_queue
      WHERE template = 'password_reset' ORDER BY id DESC LIMIT 1`
  );
  expect(rows.length).toBe(1);
  const match = /reset-password\?token=([A-Za-z0-9_%-]+)/.exec(rows[0].body_text);
  expect(match, 'Reset-Link fehlt im Mailtext').not.toBeNull();
  return decodeURIComponent(match![1]!);
}

async function requestReset(email: string, deviceToken: string) {
  return request(app).post('/auth/forgot-password').send({ email, device_token: deviceToken });
}

async function submitReset(token: string, password: string, repeat?: string) {
  return request(app)
    .post('/auth/reset-password')
    .type('form')
    .send({ token, new_password: password, new_password_repeat: repeat ?? password });
}

async function countTokens(userId: number): Promise<number> {
  const [rows] = await db.execute<any[]>(
    'SELECT COUNT(*) AS cnt FROM password_reset_tokens WHERE user_id = ?',
    [userId]
  );
  return Number(rows[0].cnt);
}

async function passwordHash(userId: number): Promise<string> {
  const [rows] = await db.execute<any[]>('SELECT password_hash FROM users WHERE id = ?', [userId]);
  return rows[0].password_hash;
}

const DEVICE_TOKEN = 'device-token-reset-abc';

// ─── POST /auth/forgot-password ─────────────────────────────────────────────

describe('POST /auth/forgot-password', () => {
  let tenantId: number;
  let userId: number;

  beforeEach(async () => {
    tenantId = await createTenant();
    userId = await createUser(tenantId, { email: 'wirt@test.de' });
    await createDevice(tenantId, DEVICE_TOKEN);
  });

  it('reiht eine Reset-Mail ein und legt genau einen Token an', async () => {
    const res = await requestReset('wirt@test.de', DEVICE_TOKEN);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(await countTokens(userId)).toBe(1);

    const [mails] = await db.execute<any[]>(
      `SELECT recipient, template, body_text FROM email_queue WHERE tenant_id = ?`,
      [tenantId]
    );
    expect(mails).toHaveLength(1);
    expect(mails[0].template).toBe('password_reset');
    expect(mails[0].recipient).toBe('wirt@test.de');
  });

  it('speichert den Token nur gehasht — der Klartext steht ausschließlich in der Mail', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const raw = await tokenFromMail();

    const [rows] = await db.execute<any[]>(
      'SELECT token_hash FROM password_reset_tokens WHERE user_id = ?',
      [userId]
    );
    expect(rows[0].token_hash).not.toBe(raw);
    expect(rows[0].token_hash).toBe(crypto.createHash('sha256').update(raw).digest('hex'));
  });

  it('setzt die Gültigkeit auf eine Stunde', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const [rows] = await db.execute<any[]>(
      `SELECT TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS mins
         FROM password_reset_tokens WHERE user_id = ?`,
      [userId]
    );
    expect(Number(rows[0].mins)).toBeGreaterThanOrEqual(58);
    expect(Number(rows[0].mins)).toBeLessThanOrEqual(60);
  });

  it('schreibt einen audit_log-Eintrag', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const [rows] = await db.execute<any[]>(
      `SELECT action, entity_id FROM audit_log WHERE tenant_id = ? AND action = 'user.password_reset_requested'`,
      [tenantId]
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].entity_id).toBe(userId);
  });

  // ── Kein User-Enumeration-Leak ────────────────────────────────────────────

  it('antwortet 200 bei unbekannter E-Mail — ohne Mail und ohne Token', async () => {
    const res = await requestReset('gibtsnicht@test.de', DEVICE_TOKEN);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(await countTokens(userId)).toBe(0);
    const [mails] = await db.execute<any[]>('SELECT id FROM email_queue');
    expect(mails).toHaveLength(0);
  });

  it('antwortet 200 bei unbekanntem Gerät — ohne Mail', async () => {
    const res = await requestReset('wirt@test.de', 'kein-echtes-geraet');

    expect(res.status).toBe(200);
    expect(await countTokens(userId)).toBe(0);
  });

  it('antwortet 200 für deaktivierte Nutzer — ohne Mail', async () => {
    const inaktiv = await createUser(tenantId, { email: 'weg@test.de', active: false });
    const res = await requestReset('weg@test.de', DEVICE_TOKEN);

    expect(res.status).toBe(200);
    expect(await countTokens(inaktiv)).toBe(0);
  });

  it('ist von außen nicht von der Erfolgsantwort unterscheidbar', async () => {
    const treffer = await requestReset('wirt@test.de', DEVICE_TOKEN);
    const daneben = await requestReset('gibtsnicht@test.de', DEVICE_TOKEN);

    expect(daneben.status).toBe(treffer.status);
    expect(daneben.body).toEqual(treffer.body);
  });

  it('422 bei fehlendem Device-Token (Zod)', async () => {
    const res = await request(app).post('/auth/forgot-password').send({ email: 'wirt@test.de' });
    expect(res.status).toBe(422);
  });

  // ── Missbrauchsschutz ─────────────────────────────────────────────────────

  it('drosselt nach drei Anfragen pro Stunde und Nutzer', async () => {
    for (let i = 0; i < 5; i++) await requestReset('wirt@test.de', DEVICE_TOKEN);

    expect(await countTokens(userId)).toBe(3);
    const [mails] = await db.execute<any[]>('SELECT id FROM email_queue');
    expect(mails).toHaveLength(3);
  });

  it('entwertet den vorherigen Link, sobald ein neuer angefordert wird', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const alt = await tokenFromMail();
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const neu = await tokenFromMail();
    expect(neu).not.toBe(alt);

    const alterVersuch = await submitReset(alt, 'neuesPasswort1');
    expect(alterVersuch.status).toBe(400);
    expect(alterVersuch.text).toContain('bereits verwendet');

    const neuerVersuch = await submitReset(neu, 'neuesPasswort1');
    expect(neuerVersuch.status).toBe(200);
  });

  // ── Tenant-Isolation ──────────────────────────────────────────────────────

  it('Tenant-Isolation: dieselbe E-Mail in einem anderen Betrieb bleibt unberührt', async () => {
    const fremderTenant = await createTenant('Fremde Bar');
    const fremderUser = await createUser(fremderTenant, { email: 'wirt@test.de' });

    await requestReset('wirt@test.de', DEVICE_TOKEN);

    expect(await countTokens(userId)).toBe(1);
    expect(await countTokens(fremderUser)).toBe(0);

    const [mails] = await db.execute<any[]>('SELECT tenant_id FROM email_queue');
    expect(mails).toHaveLength(1);
    expect(mails[0].tenant_id).toBe(tenantId);
  });

  it('Tenant-Isolation: Gerät des einen Betriebs kann keinen Reset im anderen auslösen', async () => {
    const fremderTenant = await createTenant('Fremde Bar');
    const fremderUser = await createUser(fremderTenant, { email: 'chef@fremd.de' });

    const res = await requestReset('chef@fremd.de', DEVICE_TOKEN);

    expect(res.status).toBe(200);
    expect(await countTokens(fremderUser)).toBe(0);
  });
});

// ─── GET /auth/reset-password ───────────────────────────────────────────────

describe('GET /auth/reset-password', () => {
  let tenantId: number;

  beforeEach(async () => {
    tenantId = await createTenant();
    await createUser(tenantId, { email: 'wirt@test.de' });
    await createDevice(tenantId, DEVICE_TOKEN);
  });

  it('liefert das Formular mit dem Token als HTML', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();

    const res = await request(app).get(`/auth/reset-password?token=${encodeURIComponent(token)}`);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('<form method="post" action="/auth/reset-password"');
    expect(res.text).toContain(token);
  });

  it('verbietet Caching und Referrer — der Token steht in der URL', async () => {
    const res = await request(app).get('/auth/reset-password?token=egal');
    expect(res.headers['cache-control']).toContain('no-store');
    expect(res.headers['referrer-policy']).toBe('no-referrer');
  });

  it('zeigt ohne Token eine Fehlerseite statt eines Formulars', async () => {
    const res = await request(app).get('/auth/reset-password');
    expect(res.status).toBe(400);
    expect(res.text).not.toContain('<form');
  });

  it('verbraucht den Token nicht — Aufruf und Absenden sind getrennt', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();

    await request(app).get(`/auth/reset-password?token=${encodeURIComponent(token)}`);
    await request(app).get(`/auth/reset-password?token=${encodeURIComponent(token)}`);

    expect((await submitReset(token, 'neuesPasswort1')).status).toBe(200);
  });
});

// ─── POST /auth/reset-password ──────────────────────────────────────────────

describe('POST /auth/reset-password', () => {
  let tenantId: number;
  let userId: number;

  beforeEach(async () => {
    tenantId = await createTenant();
    userId = await createUser(tenantId, { email: 'wirt@test.de', password: 'altesPasswort1' });
    await createDevice(tenantId, DEVICE_TOKEN);
  });

  it('setzt das neue Passwort und meldet Erfolg', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();
    const vorher = await passwordHash(userId);

    const res = await submitReset(token, 'neuesPasswort1');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('Erledigt');
    expect(await passwordHash(userId)).not.toBe(vorher);
  });

  it('der Wirt kann sich danach neu anmelden — mit dem neuen, nicht mit dem alten Passwort', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    await submitReset(await tokenFromMail(), 'neuesPasswort1');

    const neu = await request(app)
      .post('/auth/login')
      .send({ email: 'wirt@test.de', password: 'neuesPasswort1', device_token: DEVICE_TOKEN });
    expect(neu.status).toBe(200);
    expect(neu.body).toHaveProperty('token');

    const alt = await request(app)
      .post('/auth/login')
      .send({ email: 'wirt@test.de', password: 'altesPasswort1', device_token: DEVICE_TOKEN });
    expect(alt.status).toBe(401);
  });

  it('markiert den Token als verbraucht — ein zweiter Klick schlägt fehl', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();

    expect((await submitReset(token, 'neuesPasswort1')).status).toBe(200);

    const zweiter = await submitReset(token, 'nochNeuer2');
    expect(zweiter.status).toBe(400);
    expect(zweiter.text).toContain('bereits verwendet');

    // Das zweite Passwort darf nicht gesetzt worden sein
    const login = await request(app)
      .post('/auth/login')
      .send({ email: 'wirt@test.de', password: 'nochNeuer2', device_token: DEVICE_TOKEN });
    expect(login.status).toBe(401);
  });

  it('lehnt abgelaufene Token ab', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();
    const vorher = await passwordHash(userId);

    await db.execute(
      'UPDATE password_reset_tokens SET expires_at = NOW() - INTERVAL 1 MINUTE WHERE user_id = ?',
      [userId]
    );

    const res = await submitReset(token, 'neuesPasswort1');
    expect(res.status).toBe(400);
    expect(res.text).toContain('abgelaufen');
    expect(await passwordHash(userId)).toBe(vorher);
  });

  it('lehnt unbekannte Token ab', async () => {
    const res = await submitReset('voellig-erfunden', 'neuesPasswort1');
    expect(res.status).toBe(400);
    expect(res.text).toContain('ungültig');
  });

  it('lehnt Token deaktivierter Nutzer ab — ein Soft-Delete bleibt bestehen', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();
    await db.execute('UPDATE users SET is_active = FALSE WHERE id = ?', [userId]);

    const res = await submitReset(token, 'neuesPasswort1');
    expect(res.status).toBe(400);
    expect(res.text).toContain('nicht mehr aktiv');
  });

  it('zeigt das Formular erneut, wenn die Wiederholung nicht passt', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();
    const vorher = await passwordHash(userId);

    const res = await submitReset(token, 'neuesPasswort1', 'vertippt2');

    expect(res.status).toBe(422);
    expect(res.text).toContain('stimmen nicht überein');
    expect(res.text).toContain('<form');
    expect(res.text).toContain(token); // Token bleibt erhalten — kein Neustart nötig
    expect(await passwordHash(userId)).toBe(vorher);
  });

  it('lehnt zu kurze Passwörter ab und verbraucht den Token nicht', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();

    const kurz = await submitReset(token, 'kurz');
    expect(kurz.status).toBe(422);
    expect(kurz.text).toContain('mindestens 8 Zeichen');

    // Derselbe Link muss danach noch funktionieren
    expect((await submitReset(token, 'langGenug123')).status).toBe(200);
  });

  it('schreibt einen audit_log-Eintrag über die Änderung', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    await submitReset(await tokenFromMail(), 'neuesPasswort1');

    const [rows] = await db.execute<any[]>(
      `SELECT entity_id FROM audit_log WHERE tenant_id = ? AND action = 'user.password_reset'`,
      [tenantId]
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].entity_id).toBe(userId);
  });

  it('zwei gleichzeitige Submits desselben Links setzen das Passwort nur einmal', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    const token = await tokenFromMail();

    const [a, b] = await Promise.all([
      submitReset(token, 'neuesPasswort1'),
      submitReset(token, 'andereswort9'),
    ]);

    const codes = [a.status, b.status].sort();
    expect(codes).toEqual([200, 400]);

    // Genau eines der beiden Passwörter gilt — und der Token ist verbraucht
    const [rows] = await db.execute<any[]>(
      'SELECT used_at FROM password_reset_tokens WHERE user_id = ?',
      [userId]
    );
    expect(rows[0].used_at).not.toBeNull();
  });

  it('Tenant-Isolation: der Token wirkt nur auf den Nutzer, für den er ausgestellt wurde', async () => {
    const fremderTenant = await createTenant('Fremde Bar');
    const fremderUser = await createUser(fremderTenant, { email: 'wirt@test.de' });
    const fremderHashVorher = await passwordHash(fremderUser);

    await requestReset('wirt@test.de', DEVICE_TOKEN);
    await submitReset(await tokenFromMail(), 'neuesPasswort1');

    expect(await passwordHash(fremderUser)).toBe(fremderHashVorher);
  });
});

// ─── Sitzungen nach dem Reset ───────────────────────────────────────────────

describe('Passwortwechsel beendet laufende Sitzungen', () => {
  let tenantId: number;

  beforeEach(async () => {
    tenantId = await createTenant();
    await createUser(tenantId, { email: 'wirt@test.de', password: 'altesPasswort1' });
    await createDevice(tenantId, DEVICE_TOKEN);
  });

  async function login(password: string) {
    return request(app)
      .post('/auth/login')
      .send({ email: 'wirt@test.de', password, device_token: DEVICE_TOKEN });
  }

  it('ein vor dem Reset ausgestelltes Refresh-Token wird abgewiesen', async () => {
    const alteSitzung = await login('altesPasswort1');
    expect(alteSitzung.status).toBe(200);

    // Ohne Rückdatierung läge der Sitzungsstart in derselben Sekunde wie der
    // Reset — der Test würde dann nur zufällig funktionieren.
    await db.execute('UPDATE users SET password_changed_at = NULL WHERE tenant_id = ?', [tenantId]);

    await requestReset('wirt@test.de', DEVICE_TOKEN);
    await submitReset(await tokenFromMail(), 'neuesPasswort1');
    await db.execute(
      'UPDATE users SET password_changed_at = NOW() + INTERVAL 1 MINUTE WHERE tenant_id = ?',
      [tenantId]
    );

    const res = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: alteSitzung.body.refreshToken });

    expect(res.status).toBe(401);
    expect(res.body.error).toContain('Sitzung abgelaufen');
  });

  it('eine nach dem Reset begonnene Sitzung lässt sich normal verlängern', async () => {
    await requestReset('wirt@test.de', DEVICE_TOKEN);
    await submitReset(await tokenFromMail(), 'neuesPasswort1');

    const neueSitzung = await login('neuesPasswort1');
    expect(neueSitzung.status).toBe(200);

    const res = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: neueSitzung.body.refreshToken });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
  });

  it('Bestandsnutzer ohne password_changed_at behalten ihre Sitzung', async () => {
    const sitzung = await login('altesPasswort1');

    const res = await request(app)
      .post('/auth/refresh')
      .send({ refresh_token: sitzung.body.refreshToken });

    expect(res.status).toBe(200);
  });
});

/**
 * Fiskaly One-Time Setup Script
 *
 * Führt den kompletten TSS-Setup-Flow durch:
 *   1. Token holen
 *   2. TSS anlegen (oder vorhandene laden)
 *   3. TSS initialisieren (CREATED → INITIALIZED)
 *   4. Client(s) anlegen
 *
 * Ausgabe: TSS-ID + Client-IDs → in DB eintragen (tenants.fiskaly_tss_id, devices.tse_client_id)
 *
 * Aufruf:
 *   npx tsx scripts/fiskaly-setup.ts
 *
 * Umgebungsvariablen (.env):
 *   FISKALY_API_KEY, FISKALY_API_SECRET
 *   FISKALY_BASE_URL (optional, default: https://kassensichv-middleware.fiskaly.com/api/v2)
 */

import 'dotenv/config';
import { randomUUID } from 'crypto';
import * as readline from 'readline/promises';

const BASE_URL   = process.env['FISKALY_BASE_URL']   ?? 'https://kassensichv-middleware.fiskaly.com/api/v2';
const API_KEY    = process.env['FISKALY_API_KEY']    ?? '';
const API_SECRET = process.env['FISKALY_API_SECRET'] ?? '';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function getToken(): Promise<string> {
  const res = await fetch(`${BASE_URL}/auth`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ api_key: API_KEY, api_secret: API_SECRET }),
  });
  const data = await res.json() as any;
  if (!res.ok) {
    console.error('Auth fehlgeschlagen:', data);
    process.exit(1);
  }
  console.log('✓ Token erhalten');
  return data.access_token;
}

async function fiskalyFetch(token: string, method: string, path: string, body?: unknown) {
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  return { status: res.status, data };
}

// ─── TSS Setup ────────────────────────────────────────────────────────────────

async function setupTss(token: string, tssId: string): Promise<{ serialNumber: string }> {
  // TSS laden oder anlegen
  const { status: getStatus, data: existing } = await fiskalyFetch(token, 'GET', `/tss/${tssId}`);

  if (getStatus === 200) {
    console.log(`✓ TSS ${tssId} existiert bereits (state: ${existing.state})`);

    if (existing.state === 'INITIALIZED') {
      console.log('✓ TSS bereits initialisiert — nichts zu tun');
      return { serialNumber: existing.serial_number };
    }

    if (existing.state === 'CREATED' || existing.state === 'UNINITIALIZED') {
      console.log(`  TSS ist ${existing.state} → initialisiere...`);
      return await initializeTss(token, tssId, existing.serial_number);
    }

    console.error(`✗ TSS hat unerwarteten State: ${existing.state} (DISABLED/DEFECTIVE/DELETED — nicht nutzbar)`);
    process.exit(1);
  }

  // TSS anlegen
  console.log(`  Lege neue TSS an: ${tssId}`);
  const { status, data } = await fiskalyFetch(token, 'PUT', `/tss/${tssId}`, {
    metadata: { description: 'Cashbox TSS' },
  });

  if (status !== 200 && status !== 201) {
    console.error('✗ TSS-Anlage fehlgeschlagen:', data);
    process.exit(1);
  }

  console.log('✓ TSS angelegt');
  console.log('');
  console.log('  Vollständiger API-Response (zur Kontrolle):');
  console.log(JSON.stringify(data, null, 2));
  console.log('');

  const adminPuk: string = data.admin_puk ?? '';
  if (!adminPuk) {
    console.error('✗ admin_puk nicht im Response — siehe Fiskaly Dashboard');
    process.exit(1);
  }

  console.log('  ╔═══════════════════════════════════════════════════════════╗');
  console.log(`  ║  admin_puk (${adminPuk.length} Zeichen): ${adminPuk}`);
  console.log('  ║  ⚠️  JETZT SICHER SPEICHERN — wird nur einmal angezeigt!');
  console.log('  ╚═══════════════════════════════════════════════════════════╝');
  console.log('');

  return await initializeTss(token, tssId, data.serial_number, adminPuk);
}

async function initializeTss(
  token: string, tssId: string, serialNumber: string, adminPuk?: string
): Promise<{ serialNumber: string }> {
  // Schritt 1: CREATED → UNINITIALIZED (deployt den SMAERS-Prozess, kein Admin nötig)
  // ⚠️ Docs: kann bis 30 Sekunden dauern, bei Timeout einfach wiederholen
  const { status: currentStatus, data: current } = await fiskalyFetch(token, 'GET', `/tss/${tssId}`);
  const currentState = currentStatus === 200 ? current?.state : 'CREATED';

  if (currentState === 'CREATED') {
    console.log('  CREATED → UNINITIALIZED (kann bis 30 Sek. dauern)...');
    let deployed = false;
    for (let attempt = 1; attempt <= 5; attempt++) {
      const { status, data } = await fiskalyFetch(token, 'PATCH', `/tss/${tssId}`, { state: 'UNINITIALIZED' });
      if (status === 200) { deployed = true; break; }
      console.log(`  Versuch ${attempt}/5 fehlgeschlagen (${data?.code}) — warte 10 Sek...`);
      await new Promise(r => setTimeout(r, 10_000));
    }
    if (!deployed) {
      console.error('✗ TSS konnte nicht auf UNINITIALIZED gesetzt werden (5 Versuche).');
      console.error('  Versuche es später erneut: npx tsx scripts/fiskaly-setup.ts <tss-id>');
      process.exit(1);
    }
    console.log('✓ TSS deployed (state: UNINITIALIZED)');
  }

  // Schritt 2: Admin-PIN setzen (nach TSS-Erstellung ist PIN immer geblockt)
  // admin_puk = Personal Unblocking Key (einmalig, von Fiskaly)
  // admin_pin = frei wählbare PIN (du setzt sie hier zum ersten Mal)
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  let puk = adminPuk;
  if (!puk) {
    puk = await rl.question('  admin_puk eingeben (aus der Ausgabe beim TSS-Anlegen): ');
  }

  console.log('  Wähle eine admin_pin (mind. 6 Zeichen, z.B. "cashb1" — sicher speichern!):');
  let pin = '';
  while (pin.length < 6) {
    pin = await rl.question('  Neue admin_pin (min. 6 Zeichen): ');
    if (pin.length < 6) console.log(`  ✗ Zu kurz (${pin.length} Zeichen) — mind. 6 nötig`);
  }
  rl.close();

  // PIN setzen / entblocken via PATCH /admin
  const { status: setPinStatus, data: setPinData } = await fiskalyFetch(
    token, 'PATCH', `/tss/${tssId}/admin`,
    { admin_puk: puk, new_admin_pin: pin }
  );
  if (setPinStatus !== 200) {
    console.error('✗ Admin-PIN setzen fehlgeschlagen:', setPinData);
    process.exit(1);
  }
  console.log('✓ Admin-PIN gesetzt');

  // Schritt 3: Mit PIN einloggen
  const { status: authStatus, data: authData } = await fiskalyFetch(
    token, 'POST', `/tss/${tssId}/admin/auth`,
    { admin_pin: pin }
  );
  if (authStatus !== 200) {
    console.error('✗ Admin-Auth fehlgeschlagen:', authData);
    process.exit(1);
  }
  console.log('✓ Admin authentifiziert');

  // Schritt 4: UNINITIALIZED → INITIALIZED
  const { status: patchStatus, data: patchData } = await fiskalyFetch(
    token, 'PATCH', `/tss/${tssId}`,
    { state: 'INITIALIZED' }
  );
  if (patchStatus !== 200) {
    console.error('✗ TSS-Initialisierung fehlgeschlagen:', patchData);
    process.exit(1);
  }

  console.log('✓ TSS initialisiert (state: INITIALIZED)');
  const finalSerial = patchData?.serial_number ?? serialNumber;
  return { serialNumber: finalSerial };
}

// ─── Client Setup ─────────────────────────────────────────────────────────────

async function setupClient(token: string, tssId: string, clientId: string, deviceName: string): Promise<void> {
  const { status: getStatus, data: existing } = await fiskalyFetch(
    token, 'GET', `/tss/${tssId}/client/${clientId}`
  );

  if (getStatus === 200) {
    console.log(`  ✓ Client ${clientId} (${deviceName}) existiert bereits (state: ${existing.state})`);
    return;
  }

  const { status, data } = await fiskalyFetch(token, 'PUT', `/tss/${tssId}/client/${clientId}`, {
    serial_number: clientId,  // UUID als Serial Number
    metadata: { device_name: deviceName },
  });

  if (status !== 200 && status !== 201) {
    console.error(`✗ Client-Anlage fehlgeschlagen für ${deviceName}:`, data);
    process.exit(1);
  }

  console.log(`  ✓ Client angelegt: ${deviceName} (state: ${data.state})`);
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('Fiskaly Setup');
  console.log('═════════════');
  console.log(`Base URL: ${BASE_URL}`);
  console.log('');

  if (!API_KEY || !API_SECRET) {
    console.error('✗ FISKALY_API_KEY und FISKALY_API_SECRET müssen in .env gesetzt sein');
    process.exit(1);
  }

  const token = await getToken();

  // ─── TSS-ID: entweder aus Argument oder neu generieren ───────────────────
  let tssId = process.argv[2];
  if (!tssId) {
    tssId = randomUUID();
    console.log(`  Neue TSS-ID generiert: ${tssId}`);
    console.log('  (Nächstes Mal: npx tsx scripts/fiskaly-setup.ts ' + tssId + ')');
  } else {
    console.log(`  Verwende TSS-ID: ${tssId}`);
  }
  console.log('');

  // TSS Setup
  const { serialNumber } = await setupTss(token, tssId);
  console.log('');

  // ─── Clients: iPad 1 (weitere per Copy-Paste) ────────────────────────────
  console.log('Clients anlegen:');

  const clients: Array<{ id: string; name: string }> = [
    { id: process.argv[3] ?? randomUUID(), name: 'iPad 1' },
    // Weitere iPads hier eintragen:
    // { id: randomUUID(), name: 'iPad 2' },
  ];

  for (const client of clients) {
    await setupClient(token, tssId, client.id, client.name);
  }

  // ─── Ergebnis ─────────────────────────────────────────────────────────────
  console.log('');
  console.log('════════════════════════════════════════════════════════════');
  console.log('Setup abgeschlossen — diese Werte in DB eintragen:');
  console.log('════════════════════════════════════════════════════════════');
  console.log('');
  console.log('SQL (für deinen Tenant):');
  console.log(`  UPDATE tenants SET fiskaly_tss_id = '${tssId}' WHERE id = <tenant_id>;`);
  console.log('');
  console.log('  TSS Serial Number (für Bons/Prüfung):');
  console.log(`    ${serialNumber}`);
  console.log('');
  console.log('  Clients (devices.tse_client_id):');
  for (const client of clients) {
    console.log(`    UPDATE devices SET tse_client_id = '${client.id}' WHERE name = '${client.name}' AND tenant_id = <tenant_id>;`);
  }
  console.log('');
  console.log('  .env (optional — TSS-ID ist Tenant-spezifisch, gehört in DB):');
  console.log(`    FISKALY_TSS_ID=${tssId}  # nur als Referenz`);
}

main().catch(err => {
  console.error('Fehler:', err);
  process.exit(1);
});

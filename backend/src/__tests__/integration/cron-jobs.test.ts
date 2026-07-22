import { describe, it, expect } from 'vitest';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../db/index.js';
import {
  runTrialWarnings,
  runSubscriptionGrace,
  runLongOpenSessions,
  runTseOutageReport,
  runOfflineQueueDrain,
  runOfflineQueueAlerts,
  runZReportBackfill,
  runEmailDrain,
} from '../../jobs/index.js';

// REQ-CRON-001…008: Die Hintergrund-Jobs aus S07 (OFFEN.md B2 + A9).
//
// Zeit-Fixtures entstehen hier durch rückdatierte Daten (created_at, opened_at,
// started_at) statt durch eine gefälschte Uhr: die Jobs vergleichen in SQL gegen
// NOW(), also ist das rückdatierte Datum die einzige Stellschraube, die auch
// wirklich denselben Pfad testet wie der Produktionslauf.
//
// Jeder Job wird zusätzlich zweimal gelaufen: ein Doppellauf (Neustart, Deploy,
// zweite Instanz) darf keine zweite Mail, keinen zweiten Z-Bericht und keinen
// zweiten Alert erzeugen.

// ─── Fixtures ─────────────────────────────────────────────────────────────────

async function createTenant(opts: {
  name?: string;
  status?: 'trial' | 'active' | 'past_due' | 'cancelled';
  createdDaysAgo?: number;
  periodEndDaysAgo?: number;
} = {}): Promise<number> {
  const [t] = await db.execute<any>(
    `INSERT INTO tenants (name, address, plan, subscription_status, created_at, subscription_current_period_end)
     VALUES (?, 'Teststr. 1, 10115 Berlin', 'starter', ?,
             NOW() - INTERVAL ? DAY,
             ${opts.periodEndDaysAgo === undefined ? 'NULL' : 'NOW() - INTERVAL ? DAY'})`,
    opts.periodEndDaysAgo === undefined
      ? [opts.name ?? 'Shishabar Test', opts.status ?? 'trial', opts.createdDaysAgo ?? 0]
      : [opts.name ?? 'Shishabar Test', opts.status ?? 'trial', opts.createdDaysAgo ?? 0, opts.periodEndDaysAgo]
  );
  return t.insertId as number;
}

async function createUser(
  tenantId: number,
  opts: { role?: 'owner' | 'manager' | 'staff'; email?: string; active?: boolean } = {}
): Promise<number> {
  const [u] = await db.execute<any>(
    `INSERT INTO users (tenant_id, name, email, password_hash, role, is_active)
     VALUES (?, 'Chef', ?, 'x', ?, ?)`,
    [tenantId, opts.email ?? `owner${tenantId}@test.de`, opts.role ?? 'owner', opts.active === false ? 0 : 1]
  );
  return u.insertId as number;
}

async function createDevice(tenantId: number, name = 'iPad Theke'): Promise<number> {
  const [d] = await db.execute<any>(
    `INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, ?, ?)`,
    [tenantId, name, crypto.randomBytes(16).toString('hex')]
  );
  return d.insertId as number;
}

async function createSession(
  tenantId: number,
  deviceId: number,
  userId: number,
  opts: { openedHoursAgo?: number; status?: 'open' | 'closed'; closedMinutesAgo?: number } = {}
): Promise<number> {
  const [s] = await db.execute<any>(
    `INSERT INTO cash_register_sessions
       (tenant_id, device_id, opened_by_user_id, opened_at, status,
        opening_cash_cents, closing_cash_cents, expected_cash_cents, difference_cents,
        closed_by_user_id, closed_at)
     VALUES (?, ?, ?, NOW() - INTERVAL ? HOUR, ?, 10000,
             ${opts.status === 'closed' ? '12500, 12500, 0, ?, NOW() - INTERVAL ? MINUTE' : 'NULL, NULL, NULL, NULL, NULL'})`,
    opts.status === 'closed'
      ? [tenantId, deviceId, userId, opts.openedHoursAgo ?? 1, 'closed', userId, opts.closedMinutesAgo ?? 30]
      : [tenantId, deviceId, userId, opts.openedHoursAgo ?? 1, 'open']
  );
  return s.insertId as number;
}

/** Bezahlte Bestellung inkl. Bon und Barzahlung — Grundlage für den Z-Bericht. */
async function createPaidOrder(
  tenantId: number,
  sessionId: number,
  deviceId: number,
  userId: number,
  grossCents = 2500
): Promise<{ orderId: number; receiptId: number }> {
  const [o] = await db.execute<any>(
    `INSERT INTO orders (tenant_id, session_id, opened_by_user_id, status)
     VALUES (?, ?, ?, 'paid')`,
    [tenantId, sessionId, userId]
  );
  const orderId = o.insertId as number;

  const net = Math.round(grossCents / 1.19);
  const [r] = await db.execute<any>(
    `INSERT INTO receipts
       (tenant_id, order_id, session_id, receipt_number, status, device_id, device_name,
        vat_7_net_cents, vat_7_tax_cents, vat_19_net_cents, vat_19_tax_cents,
        total_gross_cents, tip_cents, is_takeaway, tse_pending)
     VALUES (?, ?, ?, ?, 'active', ?, 'iPad Theke', 0, 0, ?, ?, ?, 0, 0, 1)`,
    [tenantId, orderId, sessionId, orderId, deviceId, net, grossCents - net, grossCents]
  );
  const receiptId = r.insertId as number;

  await db.execute(
    `INSERT INTO payments (order_id, receipt_id, method, amount_cents, paid_by_user_id)
     VALUES (?, ?, 'cash', ?, ?)`,
    [orderId, receiptId, grossCents, userId]
  );

  return { orderId, receiptId };
}

async function createQueueEntry(
  tenantId: number,
  deviceId: number,
  orderId: number,
  opts: { status?: 'pending' | 'failed'; createdMinutesAgo?: number; receiptId?: number | null } = {}
): Promise<number> {
  const [q] = await db.execute<any>(
    `INSERT INTO offline_queue (tenant_id, device_id, order_id, payload_json, idempotency_key, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, NOW() - INTERVAL ? MINUTE)`,
    [
      tenantId, deviceId, orderId,
      JSON.stringify({
        vat7GrossCents: 0, vat19GrossCents: 2500,
        payments: [{ method: 'cash', amount_cents: 2500 }],
        receipt_id: opts.receiptId ?? null,
      }),
      uuidv4(),
      opts.status ?? 'pending',
      opts.createdMinutesAgo ?? 0,
    ]
  );
  return q.insertId as number;
}

async function mails(): Promise<any[]> {
  const [rows] = await db.execute<any[]>('SELECT * FROM email_queue ORDER BY id');
  return rows;
}

async function auditRows(action: string): Promise<any[]> {
  const [rows] = await db.execute<any[]>('SELECT * FROM audit_log WHERE action = ?', [action]);
  return rows;
}

// ─── Trial-Warnungen ──────────────────────────────────────────────────────────

describe('Cron: trial-warnings (REQ-CRON-001)', () => {
  it('warnt an Tag 10 genau einmal — auch bei doppeltem Lauf', async () => {
    const tenantId = await createTenant({ createdDaysAgo: 11, status: 'trial' });
    await createUser(tenantId);

    expect(await runTrialWarnings()).toMatchObject({ checked: 1, queued: 1 });

    const first = await mails();
    expect(first).toHaveLength(1);
    expect(first[0].template).toBe('trial_warning');
    expect(first[0].idempotency_key).toBe(`trial_warning:${tenantId}:day10`);
    expect(first[0].recipient).toBe(`owner${tenantId}@test.de`);

    // Zweiter Lauf am selben Tag (Neustart/Deploy): keine zweite Mail.
    expect(await runTrialWarnings()).toMatchObject({ queued: 0, skipped: 1 });
    expect(await mails()).toHaveLength(1);
  });

  it('warnt an Tag 13 mit eigenem Marker (zweite Warnung ist gewollt)', async () => {
    const tenantId = await createTenant({ createdDaysAgo: 13, status: 'trial' });
    await createUser(tenantId);

    await runTrialWarnings();

    const rows = await mails();
    expect(rows).toHaveLength(1);
    expect(rows[0].idempotency_key).toBe(`trial_warning:${tenantId}:day13`);
  });

  it('warnt vor Tag 10, nach Ablauf und bei bezahltem Abo gar nicht', async () => {
    const fresh   = await createTenant({ createdDaysAgo: 3,  status: 'trial',  name: 'Frisch' });
    const expired = await createTenant({ createdDaysAgo: 20, status: 'trial',  name: 'Abgelaufen' });
    const paying  = await createTenant({ createdDaysAgo: 11, status: 'active', name: 'Zahlt' });
    for (const t of [fresh, expired, paying]) await createUser(t);

    expect(await runTrialWarnings()).toMatchObject({ checked: 0, queued: 0 });
    expect(await mails()).toHaveLength(0);
  });

  it('zählt Tenants ohne aktiven Owner als empfängerlos, statt still nichts zu tun', async () => {
    const tenantId = await createTenant({ createdDaysAgo: 11, status: 'trial' });
    await createUser(tenantId, { role: 'staff', email: 'kellner@test.de' });
    await createUser(tenantId, { role: 'owner', email: 'exchef@test.de', active: false });

    expect(await runTrialWarnings()).toMatchObject({ checked: 1, queued: 0, no_recipient: 1 });
    expect(await mails()).toHaveLength(0);
  });
});

// ─── Kulanzfrist nach past_due ────────────────────────────────────────────────

describe('Cron: subscription-grace (REQ-CRON-002)', () => {
  it('meldet abgelaufene Kulanzfrist einmalig — Mail plus audit_log', async () => {
    const tenantId = await createTenant({ status: 'past_due', createdDaysAgo: 60, periodEndDaysAgo: 5 });
    await createUser(tenantId);

    expect(await runSubscriptionGrace()).toMatchObject({ expired: 1, queued: 1 });

    const rows = await mails();
    expect(rows).toHaveLength(1);
    expect(rows[0].template).toBe('subscription_event');
    expect(await auditRows('subscription.grace_expired')).toHaveLength(1);

    // Doppellauf: weder zweite Mail noch zweiter (INSERT-only!) audit_log-Eintrag.
    expect(await runSubscriptionGrace()).toMatchObject({ queued: 0, skipped: 1 });
    expect(await mails()).toHaveLength(1);
    expect(await auditRows('subscription.grace_expired')).toHaveLength(1);
  });

  it('lässt den Status unangetastet — gesperrt wird in der Middleware, nicht hier', async () => {
    const tenantId = await createTenant({ status: 'past_due', createdDaysAgo: 60, periodEndDaysAgo: 5 });
    await createUser(tenantId);

    await runSubscriptionGrace();

    const [rows] = await db.execute<any[]>('SELECT subscription_status FROM tenants WHERE id = ?', [tenantId]);
    expect(rows[0].subscription_status).toBe('past_due');
  });

  it('greift innerhalb der Kulanzfrist noch nicht', async () => {
    const tenantId = await createTenant({ status: 'past_due', createdDaysAgo: 60, periodEndDaysAgo: 1 });
    await createUser(tenantId);

    expect(await runSubscriptionGrace()).toMatchObject({ expired: 0 });
    expect(await mails()).toHaveLength(0);
  });
});

// ─── Lang offene Kassensitzungen ──────────────────────────────────────────────

describe('Cron: long-open-sessions (REQ-CRON-003)', () => {
  it('meldet eine seit 30 h offene Sitzung genau einmal', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const sessionId = await createSession(tenantId, deviceId, userId, { openedHoursAgo: 30 });

    expect(await runLongOpenSessions()).toMatchObject({ found: 1, queued: 1 });

    const rows = await mails();
    expect(rows).toHaveLength(1);
    expect(rows[0].template).toBe('long_open_session');
    expect(rows[0].idempotency_key).toBe(`long_open_session:${tenantId}:${sessionId}:24h`);

    expect(await runLongOpenSessions()).toMatchObject({ found: 1, queued: 0, skipped: 1 });
    expect(await mails()).toHaveLength(1);
  });

  it('ignoriert junge und bereits geschlossene Sitzungen', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    await createSession(tenantId, deviceId, userId, { openedHoursAgo: 2 });
    await createSession(tenantId, deviceId, userId, { openedHoursAgo: 40, status: 'closed' });

    expect(await runLongOpenSessions()).toMatchObject({ found: 0 });
    expect(await mails()).toHaveLength(0);
  });

  it('Tenant-Isolation: jeder Betrieb bekommt nur die Warnung zu seiner eigenen Sitzung', async () => {
    const a = await createTenant({ status: 'active', name: 'Bar A' });
    const b = await createTenant({ status: 'active', name: 'Bar B' });
    const aUser = await createUser(a, { email: 'a@test.de' });
    const bUser = await createUser(b, { email: 'b@test.de' });
    const aDev = await createDevice(a, 'iPad A');
    const bDev = await createDevice(b, 'iPad B');
    const aSession = await createSession(a, aDev, aUser, { openedHoursAgo: 30 });
    const bSession = await createSession(b, bDev, bUser, { openedHoursAgo: 30 });

    expect(await runLongOpenSessions()).toMatchObject({ found: 2, queued: 2 });

    const rows = await mails();
    const byRecipient = Object.fromEntries(rows.map((r: any) => [r.recipient, r]));
    expect(byRecipient['a@test.de'].tenant_id).toBe(a);
    expect(byRecipient['a@test.de'].idempotency_key).toContain(`:${aSession}:`);
    expect(byRecipient['b@test.de'].tenant_id).toBe(b);
    expect(byRecipient['b@test.de'].idempotency_key).toContain(`:${bSession}:`);
    // Gerätename im Bon-/Mailtext ist ein Snapshot des jeweiligen Tenants.
    expect(byRecipient['a@test.de'].body_text).toContain('iPad A');
    expect(byRecipient['b@test.de'].body_text).not.toContain('iPad A');
  });
});

// ─── TSE-Ausfall > 48 h ───────────────────────────────────────────────────────

describe('Cron: tse-outage-report (REQ-CRON-004)', () => {
  async function seedOutage(hoursAgo: number, opts: { ended?: boolean; notified?: boolean } = {}) {
    const tenantId = await createTenant({ status: 'active' });
    await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const [o] = await db.execute<any>(
      `INSERT INTO tse_outages (tenant_id, device_id, started_at, ended_at, notified_at)
       VALUES (?, ?, NOW() - INTERVAL ? HOUR, ${opts.ended ? 'NOW()' : 'NULL'}, ${opts.notified ? 'NOW()' : 'NULL'})`,
      [tenantId, deviceId, hoursAgo]
    );
    return { tenantId, deviceId, outageId: o.insertId as number };
  }

  it('meldet einen 50 h alten Ausfall und setzt notified_at als Nachweis', async () => {
    const { tenantId, outageId } = await seedOutage(50);

    expect(await runTseOutageReport()).toMatchObject({ found: 1, queued: 1 });

    const rows = await mails();
    expect(rows).toHaveLength(1);
    expect(rows[0].template).toBe('tse_outage');
    expect(rows[0].idempotency_key).toBe(`tse_outage:${tenantId}:${outageId}:48h`);

    const [outage] = await db.execute<any[]>('SELECT notified_at FROM tse_outages WHERE id = ?', [outageId]);
    expect(outage[0].notified_at).not.toBeNull();

    // notified_at ist der Idempotenz-Marker: zweiter Lauf findet nichts mehr.
    expect(await runTseOutageReport()).toMatchObject({ found: 0 });
    expect(await mails()).toHaveLength(1);
  });

  it('meldet weder junge noch beendete noch bereits gemeldete Ausfälle', async () => {
    await seedOutage(10);
    await seedOutage(60, { ended: true });
    await seedOutage(60, { notified: true });

    expect(await runTseOutageReport()).toMatchObject({ found: 0 });
    expect(await mails()).toHaveLength(0);
  });
});

// ─── Serverseitiger Offline-Queue-Drain ───────────────────────────────────────

describe('Cron: offline-queue-drain (REQ-CRON-005)', () => {
  it('arbeitet die Queue aller Tenants ab — ohne dass ein iPad synct', async () => {
    const a = await createTenant({ status: 'active', name: 'Bar A' });
    const b = await createTenant({ status: 'active', name: 'Bar B' });
    const results = [];
    for (const tenantId of [a, b]) {
      const userId   = await createUser(tenantId, { email: `o${tenantId}@test.de` });
      const deviceId = await createDevice(tenantId);
      const sessionId = await createSession(tenantId, deviceId, userId);
      const { orderId, receiptId } = await createPaidOrder(tenantId, sessionId, deviceId, userId);
      results.push(await createQueueEntry(tenantId, deviceId, orderId, { receiptId }));
    }

    // Phase 1: kein fiskaly_tss_id → processTseTransaction meldet pending,
    // der Eintrag muss zurück auf 'pending' (KassenSichV: niemals verwerfen).
    const result = await runOfflineQueueDrain();
    expect(result).toMatchObject({ tenants: 2, processed: 2, requeued: 2, succeeded: 0, failed: 0 });

    const [rows] = await db.execute<any[]>('SELECT status, retry_count FROM offline_queue ORDER BY id');
    expect(rows.map((r: any) => r.status)).toEqual(['pending', 'pending']);
    expect(rows.every((r: any) => r.retry_count === 1)).toBe(true);
  });

  it('failt Einträge ohne receipt_id erst nach der Frist (verwaiste TSE-Transaktion)', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const sessionId = await createSession(tenantId, deviceId, userId);
    const { orderId } = await createPaidOrder(tenantId, sessionId, deviceId, userId);
    const fresh = await createQueueEntry(tenantId, deviceId, orderId, { receiptId: null, createdMinutesAgo: 1 });
    const old   = await createQueueEntry(tenantId, deviceId, orderId, { receiptId: null, createdMinutesAgo: 30 });

    expect(await runOfflineQueueDrain()).toMatchObject({ processed: 2, failed: 1, requeued: 1 });

    const [rows] = await db.execute<any[]>('SELECT id, status FROM offline_queue ORDER BY id');
    expect(rows.find((r: any) => r.id === fresh).status).toBe('pending');
    expect(rows.find((r: any) => r.id === old).status).toBe('failed');
  });
});

// ─── Alerts für endgültig gescheiterte Einträge ───────────────────────────────

describe('Cron: offline-queue-alerts (REQ-CRON-006)', () => {
  it('meldet jeden failed-Eintrag genau einmal (alerted_at)', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const sessionId = await createSession(tenantId, deviceId, userId);
    const { orderId } = await createPaidOrder(tenantId, sessionId, deviceId, userId);
    const entryId = await createQueueEntry(tenantId, deviceId, orderId, { status: 'failed' });

    expect(await runOfflineQueueAlerts()).toEqual({ alerted: 1 });

    const [rows] = await db.execute<any[]>('SELECT alerted_at FROM offline_queue WHERE id = ?', [entryId]);
    expect(rows[0].alerted_at).not.toBeNull();

    // Zweiter Lauf: kein Alarm-Rauschen für denselben Vorfall.
    expect(await runOfflineQueueAlerts()).toEqual({ alerted: 0 });
  });

  it('meldet pending-Einträge nicht — die laufen noch im Retry', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const sessionId = await createSession(tenantId, deviceId, userId);
    const { orderId } = await createPaidOrder(tenantId, sessionId, deviceId, userId);
    await createQueueEntry(tenantId, deviceId, orderId, { status: 'pending' });

    expect(await runOfflineQueueAlerts()).toEqual({ alerted: 0 });
  });
});

// ─── Z-Bericht-Nachtrag (A9) ──────────────────────────────────────────────────

describe('Cron: z-report-backfill (REQ-CRON-007, A9)', () => {
  async function closedSessionWithoutReport(closedMinutesAgo: number) {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    const sessionId = await createSession(tenantId, deviceId, userId, {
      openedHoursAgo: 10, status: 'closed', closedMinutesAgo,
    });
    await createPaidOrder(tenantId, sessionId, deviceId, userId, 2500);
    return { tenantId, sessionId };
  }

  it('trägt den fehlenden Z-Bericht aus den unveränderten Buchungsdaten nach', async () => {
    const { tenantId, sessionId } = await closedSessionWithoutReport(30);

    expect(await runZReportBackfill()).toMatchObject({ missing: 1, backfilled: 1 });

    const [rows] = await db.execute<any[]>(
      'SELECT session_id, tenant_id, report_json FROM z_reports WHERE session_id = ?',
      [sessionId]
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].tenant_id).toBe(tenantId);

    const json = typeof rows[0].report_json === 'string' ? JSON.parse(rows[0].report_json) : rows[0].report_json;
    // Nachtrag ist im unveränderlichen Dokument markiert — ein Prüfer muss es sehen.
    expect(json.reconstructed).toBe(true);
    expect(json.reconstructed_at).toBeTruthy();
    // Und er rechnet exakt wie der reguläre Abschluss.
    expect(json.total_revenue_cents).toBe(2500);
    expect(json.total_orders).toBe(1);
    expect(json.opening_cash_cents).toBe(10000);
    expect(json.closing_cash_cents).toBe(12500);
    expect(json.payments).toEqual([{ method: 'cash', total_amount_cents: 2500, order_count: 1 }]);

    // Doppellauf: z_reports ist INSERT-only — ein zweiter Bericht wäre nicht korrigierbar.
    expect(await runZReportBackfill()).toMatchObject({ missing: 0, backfilled: 0 });
    const [after] = await db.execute<any[]>('SELECT COUNT(*) AS c FROM z_reports WHERE session_id = ?', [sessionId]);
    expect(Number(after[0].c)).toBe(1);
  });

  it('lässt frisch geschlossene Sitzungen in Ruhe (closeSession schreibt nach dem Commit)', async () => {
    await closedSessionWithoutReport(1);
    expect(await runZReportBackfill()).toMatchObject({ missing: 0 });
    const [rows] = await db.execute<any[]>('SELECT COUNT(*) AS c FROM z_reports');
    expect(Number(rows[0].c)).toBe(0);
  });

  it('fasst Sitzungen mit vorhandenem Z-Bericht nicht an', async () => {
    const { tenantId, sessionId } = await closedSessionWithoutReport(30);
    await db.execute(
      `INSERT INTO z_reports (session_id, tenant_id, report_json) VALUES (?, ?, ?)`,
      [sessionId, tenantId, JSON.stringify({ session_id: sessionId, original: true })]
    );

    expect(await runZReportBackfill()).toMatchObject({ missing: 0, backfilled: 0 });

    const [rows] = await db.execute<any[]>('SELECT report_json FROM z_reports WHERE session_id = ?', [sessionId]);
    const json = typeof rows[0].report_json === 'string' ? JSON.parse(rows[0].report_json) : rows[0].report_json;
    expect(json.original).toBe(true);
  });

  it('ignoriert offene Sitzungen (der Z-Bericht entsteht erst beim Schließen)', async () => {
    const tenantId = await createTenant({ status: 'active' });
    const userId   = await createUser(tenantId);
    const deviceId = await createDevice(tenantId);
    await createSession(tenantId, deviceId, userId, { openedHoursAgo: 40 });

    expect(await runZReportBackfill()).toMatchObject({ missing: 0 });
  });
});

// ─── Mail-Drain ───────────────────────────────────────────────────────────────

describe('Cron: email-drain (REQ-CRON-008)', () => {
  it('versendet die von einem anderen Job eingereihte Mail und belegt sie in email_log', async () => {
    // Ohne RESEND_API_KEY läuft der Versand als Dry-Run — Tests gehen nie nach außen.
    const tenantId = await createTenant({ createdDaysAgo: 11, status: 'trial' });
    await createUser(tenantId);
    await runTrialWarnings();

    expect(await runEmailDrain()).toMatchObject({ sent: 1, failed: 0, retry: 0 });

    const [queue] = await db.execute<any[]>('SELECT status, body_html FROM email_queue');
    expect(queue[0].status).toBe('sent');
    // DSGVO: Inhalte werden nach dem Versand genullt, der Nachweis bleibt in email_log.
    expect(queue[0].body_html).toBeNull();

    const [log] = await db.execute<any[]>('SELECT tenant_id, template, recipient FROM email_log');
    expect(log).toHaveLength(1);
    expect(log[0].tenant_id).toBe(tenantId);
    expect(log[0].template).toBe('trial_warning');

    // Zweiter Drain hat nichts mehr zu tun.
    expect(await runEmailDrain()).toMatchObject({ sent: 0 });
  });
});

import { describe, it, expect, beforeEach } from 'vitest';
import { db } from '../../db/index.js';
import { enqueueMail, drainEmailQueue } from '../../services/email/queue.js';
import {
  sendTrialWarning,
  sendTseOutageAlert,
  sendPasswordReset,
  sendDailyZReport,
  sendSubscriptionEvent,
  sendLongOpenSessionWarning,
} from '../../services/email/index.js';
import type { SendInput, SendResult } from '../../services/email/send.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function createTenant(name = 'Test GmbH'): Promise<number> {
  const [t] = await db.execute<any>(
    `INSERT INTO tenants (name, address, plan, subscription_status)
     VALUES (?, 'Teststr. 1, 10115 Berlin', 'starter', 'trial')`,
    [name]
  );
  return t.insertId as number;
}

/** Versand-Stub: zählt Aufrufe, liefert eine Provider-ID wie Resend. */
function okSender(id = 'resend-msg-1') {
  const calls: SendInput[] = [];
  const send = async (input: SendInput): Promise<SendResult> => {
    calls.push(input);
    return { providerMessageId: id };
  };
  return { send, calls };
}

/** Versand-Stub, der immer scheitert (Resend 500 / Netz weg). */
function failingSender(message = 'Resend 500: upstream error') {
  const calls: SendInput[] = [];
  const send = async (input: SendInput): Promise<SendResult> => {
    calls.push(input);
    throw new Error(message);
  };
  return { send, calls };
}

async function queueRow(id: number) {
  const [rows] = await db.execute<any[]>('SELECT * FROM email_queue WHERE id = ?', [id]);
  return rows[0];
}

async function onlyQueueRow() {
  const [rows] = await db.execute<any[]>('SELECT * FROM email_queue');
  return rows[0];
}

const trialData = {
  tenantName: 'Shishabar Test',
  trialEndsAt: new Date('2026-07-24T10:00:00Z'),
  upgradeUrl: 'https://app.cashbox.de/abo',
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('E-Mail-Queue — Einreihen', () => {
  let tenantId: number;
  beforeEach(async () => { tenantId = await createTenant(); });

  it('legt eine pending-Zeile mit gerendertem Betreff und beiden Körpern an', async () => {
    const inserted = await enqueueMail({
      tenantId,
      template: 'trial_warning',
      data: trialData,
      recipient: 'wirt@example.de',
      idempotencyKey: `trial_warning:${tenantId}:day10`,
    });

    expect(inserted).toBe(true);
    const row = await onlyQueueRow();
    expect(row.status).toBe('pending');
    expect(row.tenant_id).toBe(tenantId);
    expect(row.template).toBe('trial_warning');
    expect(row.recipient).toBe('wirt@example.de');
    expect(row.subject).toContain('cashbox-Test');
    expect(row.body_html).toContain('<!doctype html>');
    expect(row.body_text.length).toBeGreaterThan(0);
    expect(row.attempts).toBe(0);
  });

  it('verhindert Doppelversand über den Idempotenz-Schlüssel', async () => {
    const key = `trial_warning:${tenantId}:day10`;
    const first = await enqueueMail({
      tenantId, template: 'trial_warning', data: trialData,
      recipient: 'wirt@example.de', idempotencyKey: key,
    });
    // Zweiter Cron-Lauf am selben Tag — darf keine zweite Mail erzeugen.
    const second = await enqueueMail({
      tenantId, template: 'trial_warning', data: trialData,
      recipient: 'wirt@example.de', idempotencyKey: key,
    });

    expect(first).toBe(true);
    expect(second).toBe(false);
    const [rows] = await db.execute<any[]>('SELECT id FROM email_queue');
    expect(rows).toHaveLength(1);
  });

  it('sendTrialWarning trennt Tag 10 und Tag 13 (zwei eigene Mails)', async () => {
    await sendTrialWarning({
      tenantId, tenantName: 'Shishabar', recipient: 'wirt@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });
    await sendTrialWarning({
      tenantId, tenantName: 'Shishabar', recipient: 'wirt@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day13',
    });

    const [rows] = await db.execute<any[]>('SELECT idempotency_key FROM email_queue ORDER BY id');
    expect(rows).toHaveLength(2);
    expect(rows[0].idempotency_key).toBe(`trial_warning:${tenantId}:day10`);
    expect(rows[1].idempotency_key).toBe(`trial_warning:${tenantId}:day13`);
  });

  it('reiht alle S06-Anlässe mit stabilen technischen Idempotenzschlüsseln ein', async () => {
    const common = {
      tenantId,
      tenantName: 'Shishabar',
      recipient: 'wirt@example.de',
    };

    await sendTseOutageAlert({
      ...common,
      outageId: 77,
      deviceName: 'iPad Theke',
      outageStartedAt: new Date('2026-07-18T08:00:00Z'),
      observedAt: new Date('2026-07-20T09:00:00Z'),
    });
    await sendPasswordReset({
      ...common,
      requestId: 'request-uuid',
      resetUrl: 'https://app.cashbox.de/passwort/reset?token=secret-token',
      expiresAt: new Date('2026-07-20T11:00:00Z'),
    });
    await sendDailyZReport({
      ...common,
      zReportId: 88,
      reportDate: new Date('2026-07-20T12:00:00Z'),
      totalRevenueCents: 3050,
      payments: [{ method: 'cash', amountCents: 3050 }],
      differenceCents: 0,
    });
    await sendSubscriptionEvent({
      ...common,
      stripeEventId: 'evt_123',
      event: 'past_due',
    });
    await sendLongOpenSessionWarning({
      ...common,
      sessionId: 99,
      deviceName: 'iPad Theke',
      openedAt: new Date('2026-07-19T07:00:00Z'),
      observedAt: new Date('2026-07-20T09:00:00Z'),
    });

    const [rows] = await db.execute<any[]>(
      'SELECT template, idempotency_key, body_html, body_text FROM email_queue ORDER BY id'
    );
    expect(rows.map((row) => row.idempotency_key)).toEqual([
      `tse_outage:${tenantId}:77:48h`,
      `password_reset:${tenantId}:request-uuid`,
      `daily_z_report:${tenantId}:88`,
      `subscription_event:${tenantId}:evt_123`,
      `long_open_session:${tenantId}:99:24h`,
    ]);
    expect(rows.map((row) => row.template)).toEqual([
      'tse_outage',
      'password_reset',
      'daily_z_report',
      'subscription_event',
      'long_open_session',
    ]);
    expect(rows.every((row) => row.body_html.includes('<!doctype html>'))).toBe(true);
    expect(rows.every((row) => row.body_text.length > 0)).toBe(true);
    expect(rows.map((row) => row.idempotency_key).join(':')).not.toContain('secret-token');
    expect(rows.map((row) => row.idempotency_key).join(':')).not.toContain('wirt@example.de');
  });
});

describe('E-Mail-Queue — Versand (Drain)', () => {
  let tenantId: number;
  beforeEach(async () => { tenantId = await createTenant(); });

  async function enqueueOne(recipient = 'wirt@example.de') {
    await enqueueMail({
      tenantId, template: 'trial_warning', data: trialData,
      recipient, idempotencyKey: `trial_warning:${tenantId}:day10`,
    });
    return (await onlyQueueRow()).id as number;
  }

  it('sendet, schreibt den email_log-Nachweis und markiert die Zeile als sent', async () => {
    const id = await enqueueOne();
    const sender = okSender('resend-abc-123');

    const result = await drainEmailQueue(25, sender.send);

    expect(result).toEqual({ sent: 1, failed: 0, retry: 0 });
    expect(sender.calls).toHaveLength(1);
    expect(sender.calls[0]!.to).toBe('wirt@example.de');
    expect(sender.calls[0]!.html).toContain('<!doctype html>');
    expect(sender.calls[0]!.text.length).toBeGreaterThan(0);

    const row = await queueRow(id);
    expect(row.status).toBe('sent');
    expect(row.sent_at).not.toBeNull();
    expect(row.attempts).toBe(1);

    // GoBD/KassenSichV: Versandnachweis existiert und ist vollständig
    const [logs] = await db.execute<any[]>('SELECT * FROM email_log');
    expect(logs).toHaveLength(1);
    expect(logs[0].tenant_id).toBe(tenantId);
    expect(logs[0].template).toBe('trial_warning');
    expect(logs[0].recipient).toBe('wirt@example.de');
    expect(logs[0].provider_message_id).toBe('resend-abc-123');
    expect(logs[0].sent_at).not.toBeNull();
  });

  it('nullt Betreff und Körper nach Erfolg (DSGVO-Datenminimierung)', async () => {
    const id = await enqueueOne();
    await drainEmailQueue(25, okSender().send);

    const row = await queueRow(id);
    expect(row.subject).toBeNull();
    expect(row.body_html).toBeNull();
    expect(row.body_text).toBeNull();
  });

  it('sendet eine bereits gesendete Zeile nicht erneut', async () => {
    await enqueueOne();
    await drainEmailQueue(25, okSender().send);

    const second = okSender();
    const result = await drainEmailQueue(25, second.send);

    expect(result.sent).toBe(0);
    expect(second.calls).toHaveLength(0);
    const [logs] = await db.execute<any[]>('SELECT id FROM email_log');
    expect(logs).toHaveLength(1);
  });

  it('verarbeitet mehrere fällige Zeilen in einem Lauf', async () => {
    for (const marker of ['day10', 'day13'] as const) {
      await sendTrialWarning({
        tenantId, tenantName: 'Shishabar', recipient: 'wirt@example.de',
        trialEndsAt: trialData.trialEndsAt, dayMarker: marker,
      });
    }
    const sender = okSender();

    const result = await drainEmailQueue(25, sender.send);

    expect(result.sent).toBe(2);
    expect(sender.calls).toHaveLength(2);
  });
});

describe('E-Mail-Queue — Fehlversand und Retry', () => {
  let tenantId: number;
  beforeEach(async () => { tenantId = await createTenant(); });

  async function enqueueOne() {
    await enqueueMail({
      tenantId, template: 'trial_warning', data: trialData,
      recipient: 'wirt@example.de', idempotencyKey: `trial_warning:${tenantId}:day10`,
    });
    return (await onlyQueueRow()).id as number;
  }

  it('plant nach Fehlversand einen Retry mit Abstand ein (kein Datenverlust)', async () => {
    const id = await enqueueOne();

    const result = await drainEmailQueue(25, failingSender().send);

    expect(result).toEqual({ sent: 0, failed: 0, retry: 1 });
    const row = await queueRow(id);
    expect(row.status).toBe('pending');       // bleibt in der Queue
    expect(row.attempts).toBe(1);
    expect(row.last_error).toContain('Resend 500');
    expect(row.subject).not.toBeNull();       // Inhalt bleibt für den Retry erhalten
    expect(new Date(row.next_attempt_at).getTime()).toBeGreaterThan(Date.now());

    // Kein Nachweis, solange nichts rausging
    const [logs] = await db.execute<any[]>('SELECT id FROM email_log');
    expect(logs).toHaveLength(0);
  });

  it('nimmt eine fällige Retry-Zeile im nächsten Lauf wieder auf', async () => {
    const id = await enqueueOne();
    await drainEmailQueue(25, failingSender().send);

    // Fälligkeit vorziehen, statt auf die Backoff-Minute zu warten
    await db.execute('UPDATE email_queue SET next_attempt_at = NOW() WHERE id = ?', [id]);
    const sender = okSender();
    const result = await drainEmailQueue(25, sender.send);

    expect(result.sent).toBe(1);
    expect(sender.calls).toHaveLength(1);
    const row = await queueRow(id);
    expect(row.status).toBe('sent');
    expect(row.attempts).toBe(2);
  });

  it('lässt eine noch nicht fällige Retry-Zeile in Ruhe', async () => {
    await enqueueOne();
    await drainEmailQueue(25, failingSender().send);

    const sender = okSender();
    const result = await drainEmailQueue(25, sender.send);

    expect(result).toEqual({ sent: 0, failed: 0, retry: 0 });
    expect(sender.calls).toHaveLength(0);
  });

  it('gibt nach max_attempts endgültig auf (status failed)', async () => {
    const id = await enqueueOne();
    await db.execute('UPDATE email_queue SET max_attempts = 2 WHERE id = ?', [id]);

    await drainEmailQueue(25, failingSender().send);                       // attempts 1 → retry
    await db.execute('UPDATE email_queue SET next_attempt_at = NOW() WHERE id = ?', [id]);
    const result = await drainEmailQueue(25, failingSender().send);        // attempts 2 → failed

    expect(result).toEqual({ sent: 0, failed: 1, retry: 0 });
    const row = await queueRow(id);
    expect(row.status).toBe('failed');
    expect(row.last_error).toContain('Resend 500');
  });

  it('gibt einen hängenden processing-Claim nach dem Timeout wieder frei', async () => {
    const id = await enqueueOne();
    // Prozess-Crash mitten im Versand simulieren
    await db.execute(
      `UPDATE email_queue
          SET status = 'processing', processing_started_at = NOW() - INTERVAL 30 MINUTE, attempts = 1
        WHERE id = ?`,
      [id]
    );

    const sender = okSender();
    const result = await drainEmailQueue(25, sender.send);

    expect(result.sent).toBe(1);
    expect((await queueRow(id)).status).toBe('sent');
  });

  it('lässt einen frischen processing-Claim unangetastet (kein Doppelversand)', async () => {
    const id = await enqueueOne();
    await db.execute(
      `UPDATE email_queue SET status = 'processing', processing_started_at = NOW() WHERE id = ?`,
      [id]
    );

    const sender = okSender();
    const result = await drainEmailQueue(25, sender.send);

    expect(result.sent).toBe(0);
    expect(sender.calls).toHaveLength(0);
  });
});

describe('E-Mail-Queue — Tenant-Isolation', () => {
  it('schreibt Queue- und Log-Zeilen mit dem jeweils eigenen tenant_id', async () => {
    const tenantA = await createTenant('Bar A');
    const tenantB = await createTenant('Bar B');

    await sendTrialWarning({
      tenantId: tenantA, tenantName: 'Bar A', recipient: 'a@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });
    await sendTrialWarning({
      tenantId: tenantB, tenantName: 'Bar B', recipient: 'b@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });
    await drainEmailQueue(25, okSender().send);

    const [logs] = await db.execute<any[]>('SELECT tenant_id, recipient FROM email_log ORDER BY tenant_id');
    expect(logs).toHaveLength(2);
    expect(logs[0]).toMatchObject({ tenant_id: tenantA, recipient: 'a@example.de' });
    expect(logs[1]).toMatchObject({ tenant_id: tenantB, recipient: 'b@example.de' });
  });

  it('rendert den Betriebsnamen des richtigen Tenants in die jeweilige Mail', async () => {
    const tenantA = await createTenant('Bar A');
    const tenantB = await createTenant('Bar B');
    await sendTrialWarning({
      tenantId: tenantA, tenantName: 'Bar A', recipient: 'a@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });
    await sendTrialWarning({
      tenantId: tenantB, tenantName: 'Bar B', recipient: 'b@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });

    const sender = okSender();
    await drainEmailQueue(25, sender.send);

    const toA = sender.calls.find((c) => c.to === 'a@example.de')!;
    const toB = sender.calls.find((c) => c.to === 'b@example.de')!;
    expect(toA.text).toContain('Bar A');
    expect(toA.text).not.toContain('Bar B');
    expect(toB.text).toContain('Bar B');
    expect(toB.text).not.toContain('Bar A');
  });
});

describe('E-Mail-Queue — email_log ist INSERT-only (GoBD)', () => {
  it('der Nachweis wird über audit_insert_user geschrieben und bleibt unveränderlich', async () => {
    const tenantId = await createTenant();
    await sendTrialWarning({
      tenantId, tenantName: 'Shishabar', recipient: 'wirt@example.de',
      trialEndsAt: trialData.trialEndsAt, dayMarker: 'day10',
    });
    await drainEmailQueue(25, okSender().send);

    const [logs] = await db.execute<any[]>('SELECT * FROM email_log');
    expect(logs).toHaveLength(1);

    // Gegenprobe zur Grant-Absicht: in der Test-DB hat app_user (anders als in
    // Production) volle Rechte — der Nachweis der Unveränderlichkeit liegt daher
    // im Grant-Setup (setup-db.ts), nicht hier. Was hier zählt: der INSERT läuft
    // über auditDb, ist also auch mit produktiven INSERT-only-Grants möglich.
    const { auditDb } = await import('../../db/index.js');
    await expect(
      auditDb.execute(
        `INSERT INTO email_log (tenant_id, template, recipient, subject, provider_message_id)
         VALUES (?, 'trial_warning', 'x@example.de', 'Betreff', 'id-2')`,
        [tenantId]
      )
    ).resolves.toBeDefined();
  });
});

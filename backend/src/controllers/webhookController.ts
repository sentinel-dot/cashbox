import { Request, Response } from 'express';
import Stripe from 'stripe';
import { db } from '../db/index.js';
import { writeAuditLog } from '../services/audit.js';

// ─── Helpers ────────────────────────────────────────────────────────────────

function getStripe(): Stripe {
  const key = process.env['STRIPE_SECRET_KEY'];
  if (!key) throw new Error('STRIPE_SECRET_KEY nicht konfiguriert.');
  return new Stripe(key);
}

function getPlanFromPriceId(priceId: string): 'starter' | 'pro' | 'business' | null {
  if (priceId === process.env['STRIPE_PRICE_STARTER'])  return 'starter';
  if (priceId === process.env['STRIPE_PRICE_PRO'])      return 'pro';
  if (priceId === process.env['STRIPE_PRICE_BUSINESS']) return 'business';
  return null;
}

async function getTenantIdByCustomer(conn: any, customerId: string): Promise<number | null> {
  const [rows] = await conn.execute(
    'SELECT id FROM tenants WHERE stripe_customer_id = ? LIMIT 1',
    [customerId]
  ) as any[];
  return rows[0]?.id ?? null;
}

// Audit-Entries werden von den Handlern gesammelt und NACH conn.commit()
// geschrieben — so vermeiden wir Lock-Wait-Timeouts durch den FK-Check auf
// tenants.id, während conn noch eine exklusive Zeilen-Sperre hält.
interface PendingAudit {
  tenantId:   number;
  action:     string;
  diff:       object;
}

// ─── Event Handlers ──────────────────────────────────────────────────────────

async function onSubscriptionCreatedOrUpdated(
  conn: any,
  sub: Stripe.Subscription
): Promise<PendingAudit | null> {
  const customerId = typeof sub.customer === 'string' ? sub.customer : sub.customer.id;
  const tenantId   = await getTenantIdByCustomer(conn, customerId);
  if (!tenantId) return null; // Unbekannter Customer — ignorieren

  const priceId = sub.items.data[0]?.price?.id ?? '';
  const plan    = getPlanFromPriceId(priceId);

  if (plan) {
    await conn.execute(
      `UPDATE tenants
          SET subscription_status    = 'active',
              stripe_subscription_id = ?,
              plan                   = ?
        WHERE id = ?`,
      [sub.id, plan, tenantId]
    );
  } else {
    await conn.execute(
      `UPDATE tenants
          SET subscription_status    = 'active',
              stripe_subscription_id = ?
        WHERE id = ?`,
      [sub.id, tenantId]
    );
  }

  return {
    tenantId,
    action: 'stripe.subscription.active',
    diff:   { new: { subscription_status: 'active', plan, stripe_subscription_id: sub.id } },
  };
}

async function onSubscriptionDeleted(
  conn: any,
  sub: Stripe.Subscription
): Promise<PendingAudit | null> {
  const customerId = typeof sub.customer === 'string' ? sub.customer : sub.customer.id;
  const tenantId   = await getTenantIdByCustomer(conn, customerId);
  if (!tenantId) return null;

  // GoBD: data_retention_until = 10 Jahre ab Kündigung
  await conn.execute(
    `UPDATE tenants
        SET subscription_status  = 'cancelled',
            data_retention_until = DATE_ADD(NOW(), INTERVAL 10 YEAR)
      WHERE id = ?`,
    [tenantId]
  );

  return {
    tenantId,
    action: 'stripe.subscription.cancelled',
    diff:   { new: { subscription_status: 'cancelled' } },
  };
}

async function onInvoicePaymentSucceeded(
  conn: any,
  invoice: Stripe.Invoice
): Promise<PendingAudit | null> {
  const customerId = typeof invoice.customer === 'string'
    ? invoice.customer
    : (invoice.customer as any)?.id;
  if (!customerId) return null;

  const tenantId = await getTenantIdByCustomer(conn, customerId);
  if (!tenantId) return null;

  // period_end: Unix-Timestamp → DATETIME
  const periodEnd = invoice.period_end ? new Date(invoice.period_end * 1000) : null;

  await conn.execute(
    `UPDATE tenants SET subscription_current_period_end = ? WHERE id = ?`,
    [periodEnd, tenantId]
  );

  return null; // Kein Audit-Eintrag nötig (kein Status-Wechsel)
}

async function onInvoicePaymentFailed(
  conn: any,
  invoice: Stripe.Invoice
): Promise<PendingAudit | null> {
  const customerId = typeof invoice.customer === 'string'
    ? invoice.customer
    : (invoice.customer as any)?.id;
  if (!customerId) return null;

  const tenantId = await getTenantIdByCustomer(conn, customerId);
  if (!tenantId) return null;

  await conn.execute(
    `UPDATE tenants SET subscription_status = 'past_due' WHERE id = ?`,
    [tenantId]
  );

  return {
    tenantId,
    action: 'stripe.invoice.payment_failed',
    diff:   { new: { subscription_status: 'past_due' } },
  };
}

async function onCheckoutSessionCompleted(
  conn: any,
  session: Stripe.Checkout.Session
): Promise<PendingAudit | null> {
  const customerId     = typeof session.customer === 'string' ? session.customer : null;
  const subscriptionId = typeof session.subscription === 'string' ? session.subscription : null;
  if (!customerId || !subscriptionId) return null;

  const tenantId = await getTenantIdByCustomer(conn, customerId);
  if (!tenantId) return null;

  await conn.execute(
    `UPDATE tenants
        SET stripe_subscription_id = ?,
            subscription_status    = 'active'
      WHERE id = ?`,
    [subscriptionId, tenantId]
  );

  return {
    tenantId,
    action: 'stripe.checkout.completed',
    diff:   { new: { subscription_status: 'active', stripe_subscription_id: subscriptionId } },
  };
}

// ─── Main Webhook Handler ────────────────────────────────────────────────────

export async function stripeWebhook(req: Request, res: Response): Promise<void> {
  const sig    = req.headers['stripe-signature'] as string | undefined;
  const secret = process.env['STRIPE_WEBHOOK_SECRET'];

  if (!secret) {
    res.status(500).json({ error: 'STRIPE_WEBHOOK_SECRET nicht konfiguriert.' });
    return;
  }

  if (!sig) {
    res.status(400).json({ error: 'Stripe-Signatur fehlt.' });
    return;
  }

  // Signatur-Verifikation — rawBody ist Buffer dank express.raw() in app.ts
  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(req.body as Buffer, sig, secret);
  } catch (err: any) {
    res.status(400).json({ error: `Webhook-Signatur ungültig: ${err.message}` });
    return;
  }

  const conn = await (db as any).getConnection();
  await conn.beginTransaction();
  let pendingAudit: PendingAudit | null = null;
  try {
    // Idempotenz: Event-ID in stripe_events eintragen (PRIMARY KEY → ER_DUP_ENTRY bei Duplikat)
    try {
      await conn.execute('INSERT INTO stripe_events (id) VALUES (?)', [event.id]);
    } catch (err: any) {
      if (err.code === 'ER_DUP_ENTRY') {
        await conn.rollback();
        res.json({ received: true, skipped: 'duplicate' });
        return;
      }
      throw err;
    }

    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
        pendingAudit = await onSubscriptionCreatedOrUpdated(conn, event.data.object as Stripe.Subscription);
        break;

      case 'customer.subscription.deleted':
        pendingAudit = await onSubscriptionDeleted(conn, event.data.object as Stripe.Subscription);
        break;

      case 'invoice.payment_succeeded':
        pendingAudit = await onInvoicePaymentSucceeded(conn, event.data.object as Stripe.Invoice);
        break;

      case 'invoice.payment_failed':
        pendingAudit = await onInvoicePaymentFailed(conn, event.data.object as Stripe.Invoice);
        break;

      case 'checkout.session.completed':
        pendingAudit = await onCheckoutSessionCompleted(conn, event.data.object as Stripe.Checkout.Session);
        break;

      default:
        // Unbekannte Events: Signatur war valide → trotzdem 200 (kein Retry)
        break;
    }

    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  // Audit-Log NACH commit schreiben — auditDb hat separate Verbindung, kein Lock-Konflikt
  if (pendingAudit) {
    await writeAuditLog({
      tenantId:   pendingAudit.tenantId,
      userId:     null,
      action:     pendingAudit.action,
      entityType: 'tenant',
      entityId:   pendingAudit.tenantId,
      diff:       pendingAudit.diff,
    }).catch(console.error); // fire-and-forget: Audit darf Webhook-Response nicht blockieren
  }

  res.json({ received: true });
}

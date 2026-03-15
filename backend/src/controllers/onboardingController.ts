import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { z } from 'zod';
import Stripe from 'stripe';
import { db } from '../db/index.js';
import type { AuthPayload } from '../middleware/authMiddleware.js';

// ─── Schemas ────────────────────────────────────────────────────────────────

export const registerSchema = z.object({
  business_name: z.string().min(2).max(100),
  email:         z.string().email(),
  password:      z.string().min(8),
  address:       z.string().min(5),
  tax_number:    z.string().min(5),   // Steuernummer oder USt-IdNr. (KassenSichV-Pflichtfeld)
  device_name:   z.string().min(1).max(100),
  device_token:  z.string().min(20),
});

export const createCheckoutSessionSchema = z.object({
  plan:        z.enum(['starter', 'pro', 'business']),
  success_url: z.string().url(),
  cancel_url:  z.string().url(),
});

// ─── Helpers ────────────────────────────────────────────────────────────────

function signTokens(payload: AuthPayload): { token: string; refreshToken: string } {
  const secret = process.env['JWT_SECRET'];
  if (!secret) throw new Error('JWT_SECRET nicht konfiguriert.');

  const token = jwt.sign(payload, secret, {
    expiresIn: (process.env['JWT_EXPIRY'] ?? '15m') as any,
  });

  const refreshToken = jwt.sign(
    { ...payload, type: 'refresh' },
    secret,
    { expiresIn: (process.env['JWT_REFRESH_EXPIRY'] ?? '7d') as any }
  );

  return { token, refreshToken };
}

function getStripe(): Stripe {
  const key = process.env['STRIPE_SECRET_KEY'];
  if (!key) throw new Error('STRIPE_SECRET_KEY nicht konfiguriert.');
  return new Stripe(key);
}

const PLAN_PRICE_ENV: Record<string, string> = {
  starter:  'STRIPE_PRICE_STARTER',
  pro:      'STRIPE_PRICE_PRO',
  business: 'STRIPE_PRICE_BUSINESS',
};

// ─── Handler ────────────────────────────────────────────────────────────────

/**
 * POST /onboarding/register
 * Öffentlich — kein authMiddleware, kein deviceMiddleware.
 *
 * Erstellt Tenant + Owner-User + erstes Gerät + receipt_sequences atomar in
 * einer DB-Transaktion. Gibt ein vollständiges JWT zurück (inkl. deviceId),
 * das sofort für alle weiteren API-Calls genutzt werden kann.
 */
export async function register(req: Request, res: Response): Promise<void> {
  const {
    business_name, email, password, address, tax_number,
    device_name, device_token,
  } = req.body as z.infer<typeof registerSchema>;

  const conn = await (db as any).getConnection();
  await conn.beginTransaction();

  try {
    // 1. Tenant anlegen (trial)
    const [tenantResult] = await conn.execute(
      `INSERT INTO tenants (name, address, tax_number, subscription_status)
       VALUES (?, ?, ?, 'trial')`,
      [business_name, address, tax_number]
    ) as any[];
    const tenantId: number = tenantResult.insertId;

    // 1b. Globale E-Mail-Eindeutigkeit prüfen (onboarding-spezifisch:
    //     UNIQUE KEY uq_users_email_tenant ist nur per-Tenant — nicht ausreichend)
    const [emailCheck] = await conn.execute(
      'SELECT id FROM users WHERE email = ? LIMIT 1',
      [email]
    ) as any[];
    if ((emailCheck as any[]).length > 0) {
      await conn.rollback();
      conn.release();
      res.status(409).json({ error: 'E-Mail bereits registriert.' });
      return;
    }

    // 2. Owner-User anlegen
    const passwordHash = await bcrypt.hash(password, 10);
    const [userResult] = await conn.execute(
      `INSERT INTO users (tenant_id, name, email, password_hash, role)
       VALUES (?, ?, ?, ?, 'owner')`,
      [tenantId, business_name, email, passwordHash]
    ) as any[];
    const userId: number = userResult.insertId;

    // 3. receipt_sequences-Eintrag anlegen (KassenSichV: fortlaufend ab 1)
    await conn.execute(
      'INSERT INTO receipt_sequences (tenant_id, last_number) VALUES (?, 0)',
      [tenantId]
    );

    // 4. Erstes Gerät atomar anlegen — device_token_hash als SHA-256-Hex
    const tokenHash = crypto.createHash('sha256').update(device_token).digest('hex');
    const [deviceResult] = await conn.execute(
      'INSERT INTO devices (tenant_id, name, device_token_hash) VALUES (?, ?, ?)',
      [tenantId, device_name, tokenHash]
    ) as any[];
    const deviceId: number = deviceResult.insertId;

    await conn.commit();

    const payload: AuthPayload = { userId, tenantId, deviceId, role: 'owner' };
    const { token, refreshToken } = signTokens(payload);

    res.status(201).json({
      token,
      refreshToken,
      user:   { id: userId,   name: business_name, role: 'owner' },
      device: { id: deviceId, name: device_name },
    });
  } catch (err: any) {
    await conn.rollback();
    if (err.code === 'ER_DUP_ENTRY') {
      res.status(409).json({ error: 'E-Mail bereits registriert.' });
    } else {
      throw err;
    }
  } finally {
    conn.release();
  }
}

/**
 * POST /onboarding/create-checkout-session
 * Erfordert auth + device (normaler Middleware-Stack ohne sessionMiddleware).
 *
 * Legt Stripe-Customer an (falls noch nicht vorhanden), speichert
 * stripe_customer_id im Tenant, und gibt eine Checkout-Session-URL zurück.
 */
export async function createCheckoutSession(req: Request, res: Response): Promise<void> {
  const { plan, success_url, cancel_url } = req.body as z.infer<typeof createCheckoutSessionSchema>;
  const tenantId = req.auth!.tenantId;

  const priceId = process.env[PLAN_PRICE_ENV[plan]];
  if (!priceId) {
    res.status(500).json({ error: `Stripe-Preis für Plan '${plan}' nicht konfiguriert.` });
    return;
  }

  // Tenant laden (tenants hat keine email-Spalte — owner-Email steht in users)
  const [rows] = await db.execute<any[]>(
    'SELECT name, stripe_customer_id FROM tenants WHERE id = ?',
    [tenantId]
  );
  if (rows.length === 0) {
    res.status(404).json({ error: 'Tenant nicht gefunden.' });
    return;
  }
  const tenant = rows[0];

  const stripe = getStripe();
  let customerId: string = tenant.stripe_customer_id ?? '';

  // Stripe-Customer anlegen wenn noch nicht vorhanden
  if (!customerId) {
    const customer = await stripe.customers.create({
      name:     tenant.name,
      metadata: { tenant_id: String(tenantId) },
    });
    customerId = customer.id;

    await db.execute(
      'UPDATE tenants SET stripe_customer_id = ? WHERE id = ?',
      [customerId, tenantId]
    );
  }

  // Checkout-Session erstellen
  const session = await stripe.checkout.sessions.create({
    customer:   customerId,
    mode:       'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    success_url,
    cancel_url,
    metadata:   { tenant_id: String(tenantId) },
  });

  res.json({ checkout_url: session.url });
}

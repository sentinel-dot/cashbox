import { Request, Response, NextFunction } from 'express';
import { db } from '../db/index.js';

const TRIAL_DAYS        = 14;
const GRACE_PERIOD_DAYS = 3;

export async function subscriptionMiddleware(req: Request, res: Response, next: NextFunction): Promise<void> {
  if (!req.auth) {
    res.status(401).json({ error: 'Nicht authentifiziert.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT subscription_status, created_at, subscription_current_period_end FROM tenants WHERE id = ?',
    [req.auth.tenantId]
  );

  if (rows.length === 0) {
    res.status(403).json({ error: 'Tenant nicht gefunden.' });
    return;
  }

  const { subscription_status: status, created_at, subscription_current_period_end } = rows[0];

  if (status === 'trial') {
    const trialExpiry = new Date(created_at);
    trialExpiry.setDate(trialExpiry.getDate() + TRIAL_DAYS);

    if (new Date() > trialExpiry) {
      res.status(402).json({ error: 'Trial abgelaufen. Bitte Abonnement abschließen.' });
      return;
    }

    res.setHeader('X-Trial-Expires', trialExpiry.toISOString());
    next();
    return;
  }

  if (status === 'cancelled') {
    res.status(402).json({ error: 'Abonnement gekündigt. Bitte erneuern.' });
    return;
  }

  if (status === 'past_due') {
    if (subscription_current_period_end) {
      const graceExpiry = new Date(subscription_current_period_end);
      graceExpiry.setDate(graceExpiry.getDate() + GRACE_PERIOD_DAYS);
      if (new Date() > graceExpiry) {
        res.status(402).json({ error: 'Zahlung überfällig. Bitte Zahlungsmethode aktualisieren.' });
        return;
      }
    }
    res.setHeader('X-Subscription-Warning', `Zahlung überfällig. Grace period: ${GRACE_PERIOD_DAYS} Tage.`);
  }

  next();
}

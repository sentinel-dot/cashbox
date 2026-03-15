import { Request, Response, NextFunction } from 'express';
import { db } from '../db/index.js';

const PLAN_LIMITS = {
  starter:  { devices: 1,  tables: 10,  products: 50 },
  pro:      { devices: 3,  tables: 30,  products: 200 },
  business: { devices: 10, tables: Infinity, products: Infinity },
} as const;

type Plan = keyof typeof PLAN_LIMITS;
type Resource = keyof typeof PLAN_LIMITS.starter;

// Factory: gibt Middleware zurück die prüft ob Limit für eine Ressource erreicht ist
export function planLimitMiddleware(resource: Resource) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    if (!req.auth) {
      res.status(401).json({ error: 'Nicht authentifiziert.' });
      return;
    }

    const [rows] = await db.execute<any[]>(
      'SELECT plan FROM tenants WHERE id = ?',
      [req.auth.tenantId]
    );

    if (rows.length === 0) {
      res.status(403).json({ error: 'Tenant nicht gefunden.' });
      return;
    }

    const plan = rows[0].plan as Plan;
    const limit = PLAN_LIMITS[plan]?.[resource] ?? 0;

    if (limit === Infinity) {
      next();
      return;
    }

    // Count current usage
    const tableMap: Record<Resource, string> = {
      devices:  'SELECT COUNT(*) as cnt FROM devices WHERE tenant_id = ? AND is_revoked = FALSE',
      tables:   'SELECT COUNT(*) as cnt FROM tables WHERE tenant_id = ? AND is_active = TRUE',
      products: 'SELECT COUNT(*) as cnt FROM products WHERE tenant_id = ? AND is_active = TRUE',
    };

    const [countRows] = await db.execute<any[]>(tableMap[resource], [req.auth.tenantId]);
    const current = countRows[0]?.cnt ?? 0;

    if (current >= limit) {
      res.status(403).json({
        error: `Plan-Limit erreicht: ${resource} (${current}/${limit}). Upgrade erforderlich.`,
        limit,
        current,
        plan,
      });
      return;
    }

    next();
  };
}

import { Request, Response, NextFunction } from 'express';
import { db } from '../db/index.js';

declare global {
  namespace Express {
    interface Request {
      sessionId?: number;
    }
  }
}

// Nur für Order- und Payment-Routen. Gibt 409 zurück wenn keine offene Kassensitzung.
export async function sessionMiddleware(req: Request, res: Response, next: NextFunction): Promise<void> {
  if (!req.auth) {
    res.status(401).json({ error: 'Nicht authentifiziert.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    `SELECT id FROM cash_register_sessions
     WHERE tenant_id = ? AND device_id = ? AND status = 'open'
     LIMIT 1`,
    [req.auth.tenantId, req.auth.deviceId]
  );

  if (rows.length === 0) {
    res.status(409).json({ error: 'Keine offene Kassensitzung. Bitte Sitzung zuerst öffnen.' });
    return;
  }

  req.sessionId = rows[0].id;
  next();
}

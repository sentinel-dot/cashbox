import { Request, Response, NextFunction } from 'express';
import { db } from '../db/index.js';

export async function deviceMiddleware(req: Request, res: Response, next: NextFunction): Promise<void> {
  if (!req.auth) {
    res.status(401).json({ error: 'Nicht authentifiziert.' });
    return;
  }

  const [rows] = await db.execute<any[]>(
    'SELECT id, is_revoked FROM devices WHERE id = ? AND tenant_id = ?',
    [req.auth.deviceId, req.auth.tenantId]
  );

  if (rows.length === 0 || rows[0].is_revoked) {
    res.status(401).json({ error: 'Gerät nicht autorisiert oder gesperrt.' });
    return;
  }

  // Update last_seen_at (fire-and-forget, kein await)
  db.execute('UPDATE devices SET last_seen_at = NOW() WHERE id = ?', [req.auth.deviceId]).catch(() => {});

  next();
}

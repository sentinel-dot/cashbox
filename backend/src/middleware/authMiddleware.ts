import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

export interface AuthPayload {
  userId: number;
  tenantId: number;
  deviceId: number;
  role: 'owner' | 'manager' | 'staff';
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthPayload;
      tenantId?: number;
      deviceId?: number;
    }
  }
}

export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Kein Token angegeben.' });
    return;
  }

  const token = header.slice(7);
  const secret = process.env['JWT_SECRET'];
  if (!secret) {
    res.status(500).json({ error: 'Server-Konfigurationsfehler.' });
    return;
  }

  try {
    const payload = jwt.verify(token, secret) as AuthPayload & { type?: string };
    if (payload.type === 'refresh') {
      res.status(401).json({ error: 'Refresh-Token darf nicht als Access-Token verwendet werden.' });
      return;
    }
    req.auth = payload;
    next();
  } catch {
    res.status(401).json({ error: 'Token ungültig oder abgelaufen.' });
  }
}

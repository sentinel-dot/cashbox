import { Request, Response, NextFunction } from 'express';

type Role = 'owner' | 'manager' | 'staff';

/**
 * Rollen-Guard: 403 wenn die JWT-Rolle nicht in der Whitelist ist.
 * Nach authMiddleware einhängen (req.auth muss gesetzt sein).
 */
export function requireRole(...allowed: Role[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.auth) {
      res.status(401).json({ error: 'Nicht authentifiziert.' });
      return;
    }
    if (!allowed.includes(req.auth.role)) {
      res.status(403).json({ error: 'Keine Berechtigung für diese Aktion.' });
      return;
    }
    next();
  };
}

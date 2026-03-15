import { Request, Response, NextFunction } from 'express';

// tenant_id kommt IMMER aus JWT, nie aus Request-Body oder URL-Params
export function tenantMiddleware(req: Request, res: Response, next: NextFunction): void {
  if (!req.auth) {
    res.status(401).json({ error: 'Nicht authentifiziert.' });
    return;
  }
  req.tenantId = req.auth.tenantId;
  req.deviceId = req.auth.deviceId;
  next();
}

import { Router } from 'express';
import { loginRateLimit } from '../middleware/rateLimitMiddleware.js';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  loginSchema,
  refreshSchema,
  pinSchema,
} from '../controllers/authController.js';
import * as auth from '../controllers/authController.js';

const router = Router();

// POST /auth/login — Email + Passwort → JWT + RefreshToken
router.post(
  '/login',
  loginRateLimit,
  validationMiddleware(loginSchema),
  auth.login
);

// POST /auth/refresh — RefreshToken → neues JWT
router.post(
  '/refresh',
  validationMiddleware(refreshSchema),
  auth.refresh
);

// POST /auth/logout — JWT invalidieren (client-seitig + refresh_token in DB löschen)
router.post(
  '/logout',
  authMiddleware,
  auth.logout
);

// POST /auth/pin — PIN-basierter Benutzerwechsel auf Gerät
// Kein authMiddleware: Gerät sendet device_token + PIN, bekommt neues JWT für anderen User
router.post(
  '/pin',
  loginRateLimit,
  validationMiddleware(pinSchema),
  auth.pinSwitch
);

export default router;

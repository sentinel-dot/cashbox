import { Router, urlencoded } from 'express';
import { loginRateLimit, passwordResetRateLimit } from '../middleware/rateLimitMiddleware.js';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  loginSchema,
  refreshSchema,
  pinSchema,
  forgotPasswordSchema,
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

// POST /auth/forgot-password — Reset-Link anfordern (antwortet immer 200)
router.post(
  '/forgot-password',
  passwordResetRateLimit,
  validationMiddleware(forgotPasswordSchema),
  auth.forgotPassword
);

// GET /auth/reset-password?token=… — server-gerenderte Seite aus der Mail.
// Einziger HTML-Endpoint des Backends (S08-Entscheidung: kein Web-Frontend
// vorhanden, der Link muss trotzdem auf jedem Gerät funktionieren).
router.get(
  '/reset-password',
  passwordResetRateLimit,
  auth.showResetPasswordPage
);

// POST /auth/reset-password — Submit des Formulars von oben.
// Eigener urlencoded-Parser: app.ts registriert nur express.json(), ein
// Browser-Formular sendet aber application/x-www-form-urlencoded.
// Validierung per safeParse im Controller, weil die Antwort HTML ist —
// Begründung am Schema in authController.ts.
router.post(
  '/reset-password',
  passwordResetRateLimit,
  urlencoded({ extended: false }),
  auth.resetPassword
);

export default router;

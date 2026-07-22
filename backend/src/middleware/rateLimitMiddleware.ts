import rateLimit, { ipKeyGenerator } from 'express-rate-limit';

const isTest = () => process.env['NODE_ENV'] === 'test';

export const loginRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  skip: isTest,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Zu viele Login-Versuche. Bitte 1 Minute warten.' },
});

// S08: gilt für „Link anfordern" UND für das Absenden der Reset-Seite.
// Bewusst großzügiger als der Login (ein Tippfehler bei „Passwort wiederholen"
// darf niemanden aussperren) und über 15 min statt 1 min gemessen. Gegen
// Mail-Bombing eines einzelnen Postfachs greift zusätzlich das Stundenlimit
// pro Nutzer in `services/passwordReset.ts`.
export const passwordResetRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  skip: isTest,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Zu viele Anfragen. Bitte 15 Minuten warten.' },
});

export const onboardingRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  skip: isTest,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Zu viele Registrierungsversuche. Bitte 1 Minute warten.' },
});

export const apiRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  skip: isTest,
  // Läuft global vor Auth → tenantId immer undefined → effektiv per-IP.
  // Per-Tenant-Fairness → Phase 4+: nach tenantMiddleware verschieben.
  keyGenerator: (req) => ipKeyGenerator(req.ip ?? ''),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Rate limit überschritten.' },
});

export const syncRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  skip: isTest,
  keyGenerator: (req) => (req as any).deviceId?.toString() ?? ipKeyGenerator(req.ip ?? ''),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Sync rate limit überschritten.' },
});

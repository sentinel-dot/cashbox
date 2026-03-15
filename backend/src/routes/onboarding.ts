import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { onboardingRateLimit } from '../middleware/rateLimitMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  registerSchema,
  createCheckoutSessionSchema,
  register,
  createCheckoutSession,
} from '../controllers/onboardingController.js';

const router = Router();

// POST /onboarding/register — öffentlich, kein Auth (User existiert noch nicht)
// Spezielles Rate-Limit: 3 Versuche/Minute/IP (verhindert Tenant-Spam).
router.post(
  '/register',
  onboardingRateLimit,
  validationMiddleware(registerSchema),
  register
);

// POST /onboarding/create-checkout-session — Auth erforderlich (Tenant existiert bereits)
router.post(
  '/create-checkout-session',
  authMiddleware,
  deviceMiddleware,
  tenantMiddleware,
  subscriptionMiddleware,
  validationMiddleware(createCheckoutSessionSchema),
  createCheckoutSession
);

export default router;

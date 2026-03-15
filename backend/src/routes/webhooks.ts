import { Router } from 'express';
import { stripeWebhook } from '../controllers/webhookController.js';

const router = Router();

// POST /webhooks/stripe
// Kein authMiddleware — Stripe authentifiziert via HMAC-Signatur (constructEvent).
// rawBody kommt als Buffer: app.ts registriert express.raw() für /webhooks/stripe
// VOR express.json(), damit der Buffer nicht überschrieben wird.
router.post('/stripe', stripeWebhook);

export default router;

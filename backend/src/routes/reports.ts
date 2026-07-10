import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { requireRole } from '../middleware/roleMiddleware.js';
import { getDailyReport, getSummaryReport } from '../controllers/reportsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// Query-Param-Validierung erfolgt im Controller via Zod (kein req.body hier)
router.get('/daily',   requireRole('owner', 'manager'), getDailyReport);
router.get('/summary', requireRole('owner', 'manager'), getSummaryReport);

export default router;

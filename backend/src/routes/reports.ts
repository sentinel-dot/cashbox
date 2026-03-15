import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { getDailyReport, getSummaryReport } from '../controllers/reportsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// Query-Param-Validierung erfolgt im Controller via Zod (kein req.body hier)
router.get('/daily',   getDailyReport);
router.get('/summary', getSummaryReport);

export default router;

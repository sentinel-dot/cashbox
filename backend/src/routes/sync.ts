import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { getOfflineQueueStatus, syncOfflineQueue } from '../controllers/offlineQueueController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

router.get( '/offline-queue',  getOfflineQueueStatus);
router.post('/offline-queue',  syncOfflineQueue);

export default router;

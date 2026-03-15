import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { sessionMiddleware } from '../middleware/sessionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import { listReceipts, getReceipt } from '../controllers/receiptsController.js';
import { cancelReceiptSchema, cancelReceipt } from '../controllers/cancellationsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

router.get('/',    listReceipts);
router.get('/:id', getReceipt);
router.post('/:id/cancel', sessionMiddleware, validationMiddleware(cancelReceiptSchema), cancelReceipt);

export default router;

import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import { updateTenantSchema, getTenant, updateTenant } from '../controllers/tenantsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

router.get( '/me', getTenant);
router.patch('/me', validationMiddleware(updateTenantSchema), updateTenant);

export default router;

import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { planLimitMiddleware } from '../middleware/planMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  registerDeviceSchema,
  listDevices,
  registerDevice,
  revokeDevice,
} from '../controllers/devicesController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// GET /devices
router.get('/', listDevices);

// POST /devices/register — Plan-Limit prüfen bevor Gerät angelegt wird
router.post(
  '/register',
  planLimitMiddleware('devices'),
  validationMiddleware(registerDeviceSchema),
  registerDevice
);

// POST /devices/:id/revoke
router.post('/:id/revoke', revokeDevice);

export default router;

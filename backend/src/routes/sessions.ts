import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  openSessionSchema, closeSessionSchema, movementSchema,
  openSession, getCurrentSession, closeSession,
  getSession, getZReport, addMovement,
} from '../controllers/sessionsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

router.post('/open',               validationMiddleware(openSessionSchema),  openSession);
router.get( '/current',            getCurrentSession);
router.post('/close',              validationMiddleware(closeSessionSchema), closeSession);
router.get( '/:id',                getSession);
router.get( '/:id/z-report',       getZReport);
router.post('/:id/movements',      validationMiddleware(movementSchema),     addMovement);

export default router;

import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  createZoneSchema,  updateZoneSchema,
  createTableSchema, updateTableSchema,
  listZones,   createZone,   updateZone,
  listTables,  createTable,  updateTable,  deleteTable,
} from '../controllers/tablesController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// ─── Zonen ───────────────────────────────────────────────────────────────────
router.get( '/zones',     listZones);
router.post('/zones',     validationMiddleware(createZoneSchema), createZone);
router.patch('/zones/:id', validationMiddleware(updateZoneSchema), updateZone);

// ─── Tische ──────────────────────────────────────────────────────────────────
router.get( '/',     listTables);
router.post('/',     validationMiddleware(createTableSchema), createTable);
router.patch('/:id', validationMiddleware(updateTableSchema), updateTable);
router.delete('/:id', deleteTable);

export default router;

import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { triggerExport, getExportStatus, downloadExportFile } from '../controllers/exportController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// Query-Param-Validierung im Controller via Zod
router.get('/dsfinvk',                       triggerExport);
router.get('/dsfinvk/:exportId/status',      getExportStatus);
router.get('/dsfinvk/:exportId/file',        downloadExportFile);

export default router;

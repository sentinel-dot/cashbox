import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import { requireRole } from '../middleware/roleMiddleware.js';
import {
  createGroupSchema,  updateGroupSchema,
  createOptionSchema, updateOptionSchema,
  listGroups,    createGroup,  updateGroup,  deleteGroup,
  createOption,  updateOption, deleteOption,
} from '../controllers/modifierGroupsController.js';

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// ─── Gruppen ──────────────────────────────────────────────────────────────────
router.get('/',     listGroups);
router.post('/',    requireRole('owner', 'manager'), validationMiddleware(createGroupSchema),  createGroup);
router.patch('/:id', requireRole('owner', 'manager'), validationMiddleware(updateGroupSchema), updateGroup);
router.delete('/:id', requireRole('owner', 'manager'), deleteGroup);

// ─── Optionen (verschachtelt unter Gruppe) ────────────────────────────────────
router.post('/:id/options',          requireRole('owner', 'manager'), validationMiddleware(createOptionSchema), createOption);
router.patch('/:id/options/:optId',  requireRole('owner', 'manager'), validationMiddleware(updateOptionSchema), updateOption);
router.delete('/:id/options/:optId', requireRole('owner', 'manager'), deleteOption);

export default router;

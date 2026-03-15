import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  createUserSchema,
  updateUserSchema,
  listUsers,
  createUser,
  updateUser,
  deleteUser,
} from '../controllers/usersController.js';

const router = Router();

// Alle User-Routen erfordern Auth
router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// GET /users
router.get('/', listUsers);

// POST /users
router.post('/', validationMiddleware(createUserSchema), createUser);

// PATCH /users/:id
router.patch('/:id', validationMiddleware(updateUserSchema), updateUser);

// DELETE /users/:id → soft delete
router.delete('/:id', deleteUser);

export default router;

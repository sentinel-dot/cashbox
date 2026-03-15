import { Router } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { sessionMiddleware } from '../middleware/sessionMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  createOrderSchema, addItemSchema, cancelOrderSchema,
  listOrders, createOrder, getOrder,
  addItem, removeItem, cancelOrder,
} from '../controllers/ordersController.js';
import { payOrderSchema, payOrder } from '../controllers/paymentsController.js';
import { splitBillSchema, splitBill } from '../controllers/splitBillController.js';

const router = Router();

// Alle Order-Routen benötigen eine offene Kassensitzung
router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware, sessionMiddleware);

router.get( '/',                    listOrders);
router.post('/',                    validationMiddleware(createOrderSchema), createOrder);
router.get( '/:id',                 getOrder);
router.post('/:id/items',           validationMiddleware(addItemSchema),    addItem);
router.delete('/:id/items/:itemId', removeItem);
router.post('/:id/cancel',          validationMiddleware(cancelOrderSchema), cancelOrder);
router.post('/:id/pay',             validationMiddleware(payOrderSchema),    payOrder);
router.post('/:id/pay/split',       validationMiddleware(splitBillSchema),   splitBill);

export default router;

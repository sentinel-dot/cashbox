import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { planLimitMiddleware } from '../middleware/planMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import {
  createCategorySchema, updateCategorySchema,
  createProductSchema,  updateProductSchema,  changePriceSchema,
  listCategories, createCategory, updateCategory, deleteCategory,
  listProducts,   createProduct,  updateProduct,  deleteProduct, changePrice,
} from '../controllers/productsController.js';

const IMMUTABLE_PRICE_FIELDS = ['price_cents', 'vat_rate_inhouse', 'vat_rate_takeaway'];

function rejectImmutablePriceFields(req: Request, res: Response, next: NextFunction): void {
  const found = IMMUTABLE_PRICE_FIELDS.find(f => f in req.body);
  if (found) {
    res.status(400).json({
      error: `'${found}' darf nicht über PATCH geändert werden.`,
      hint: 'Preisänderungen erfordern einen neuen product_price_history-Eintrag (GoBD-Pflicht). Endpoint: POST /products/:id/price',
    });
    return;
  }
  next();
}

const router = Router();

router.use(authMiddleware, deviceMiddleware, tenantMiddleware, subscriptionMiddleware);

// ─── Kategorien ──────────────────────────────────────────────────────────────
router.get( '/categories',     listCategories);
router.post('/categories',     validationMiddleware(createCategorySchema), createCategory);
router.patch('/categories/:id', validationMiddleware(updateCategorySchema), updateCategory);
router.delete('/categories/:id', deleteCategory);

// ─── Produkte ─────────────────────────────────────────────────────────────────
router.get('/',          listProducts);
router.post('/',         planLimitMiddleware('products'), validationMiddleware(createProductSchema), createProduct);
router.post('/:id/price', validationMiddleware(changePriceSchema), changePrice);
router.patch('/:id',     rejectImmutablePriceFields, validationMiddleware(updateProductSchema), updateProduct);
router.delete('/:id',    deleteProduct);

export default router;

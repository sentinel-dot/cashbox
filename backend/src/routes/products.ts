import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/authMiddleware.js';
import { deviceMiddleware } from '../middleware/deviceMiddleware.js';
import { tenantMiddleware } from '../middleware/tenantMiddleware.js';
import { subscriptionMiddleware } from '../middleware/subscriptionMiddleware.js';
import { planLimitMiddleware } from '../middleware/planMiddleware.js';
import { validationMiddleware } from '../middleware/validationMiddleware.js';
import { requireRole } from '../middleware/roleMiddleware.js';
import {
  createCategorySchema, updateCategorySchema,
  createProductSchema,  updateProductSchema,  changePriceSchema,
  reorderProductsSchema, reorderCategoriesSchema,
  listCategories, createCategory, updateCategory, deleteCategory,
  listProducts,   createProduct,  updateProduct,  deleteProduct, changePrice,
  reorderProducts, reorderCategories,
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
router.post('/categories',     requireRole('owner', 'manager'), validationMiddleware(createCategorySchema), createCategory);
// /categories/reorder VOR /categories/:id registrieren (sonst matcht :id = "reorder")
router.patch('/categories/reorder', requireRole('owner', 'manager'), validationMiddleware(reorderCategoriesSchema), reorderCategories);
router.patch('/categories/:id', requireRole('owner', 'manager'), validationMiddleware(updateCategorySchema), updateCategory);
router.delete('/categories/:id', requireRole('owner', 'manager'), deleteCategory);

// ─── Produkte ─────────────────────────────────────────────────────────────────
router.get('/',          listProducts);
router.post('/',         requireRole('owner', 'manager'), planLimitMiddleware('products'), validationMiddleware(createProductSchema), createProduct);
// /reorder VOR /:id-Routen registrieren
router.patch('/reorder', requireRole('owner', 'manager'), validationMiddleware(reorderProductsSchema), reorderProducts);
router.post('/:id/price', requireRole('owner', 'manager'), validationMiddleware(changePriceSchema), changePrice);
router.patch('/:id',     requireRole('owner', 'manager'), rejectImmutablePriceFields, validationMiddleware(updateProductSchema), updateProduct);
router.delete('/:id',    requireRole('owner', 'manager'), deleteProduct);

export default router;

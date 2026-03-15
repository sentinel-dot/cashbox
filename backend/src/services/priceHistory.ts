import { auditDb } from '../db/index.js';

interface PriceHistoryEntry {
  productId:        number;
  tenantId:         number;
  priceCents:       number;
  vatRateInhouse:   '7' | '19';
  vatRateTakeaway:  '7' | '19';
  changedByUserId:  number;
  validFrom?:       Date;
}

// GoBD: NUR INSERT — auditDb hat keine UPDATE/DELETE-Rechte auf product_price_history
export async function writePriceHistory(entry: PriceHistoryEntry): Promise<void> {
  await auditDb.execute(
    `INSERT INTO product_price_history
       (product_id, tenant_id, price_cents, vat_rate_inhouse, vat_rate_takeaway, changed_by_user_id, valid_from)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      entry.productId,
      entry.tenantId,
      entry.priceCents,
      entry.vatRateInhouse,
      entry.vatRateTakeaway,
      entry.changedByUserId,
      entry.validFrom ?? new Date(),
    ]
  );
}

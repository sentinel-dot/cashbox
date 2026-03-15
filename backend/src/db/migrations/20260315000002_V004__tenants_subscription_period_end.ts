import { Connection } from 'mysql2/promise';

export async function up(db: Connection): Promise<void> {
  // Ende des aktuellen Stripe-Abrechnungszeitraums — wird bei invoice.payment_succeeded gesetzt.
  // Nicht GoBD-relevant (operatives Feld), UPDATE ist erlaubt.
  await db.execute(`
    ALTER TABLE tenants
    ADD COLUMN subscription_current_period_end DATETIME NULL
      COMMENT 'Ende des aktuellen Stripe-Abrechnungszeitraums (aus invoice.payment_succeeded)'
  `);
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE tenants DROP COLUMN subscription_current_period_end');
}

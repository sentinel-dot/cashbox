import { auditDb } from '../db/index.js';

export interface OrderItemModifierEntry {
  modifierOptionId: number;
  optionName:       string;
  priceDeltaCents:  number;
}

// GoBD: NUR INSERT — auditDb hat keine UPDATE/DELETE-Rechte auf order_item_modifiers.
// Eigene Funktion (statt inline im Controller), damit der Fehlerpfad im
// Integrationstest injizierbar ist: die Kompensation in addItem (A3) hängt daran.
export async function writeOrderItemModifiers(
  orderItemId: number,
  entries: OrderItemModifierEntry[]
): Promise<void> {
  for (const e of entries) {
    await auditDb.execute(
      `INSERT INTO order_item_modifiers (order_item_id, modifier_option_id, option_name, price_delta_cents)
       VALUES (?, ?, ?, ?)`,
      [orderItemId, e.modifierOptionId, e.optionName, e.priceDeltaCents]
    );
  }
}

// db-grants.test.ts — REQ-SEC-A6: audit_insert_user darf ausschließlich in die
// append-only-Tabellen schreiben. Der zweite DB-User ist die Verteidigungslinie
// dafür, dass Audit-/GoBD-Zeilen nie überschrieben werden — mit einem pauschalen
// INSERT auf `db`.* könnte derselbe Account auch orders, payments oder users
// befüllen und wäre damit wertlos.
//
// Die Grants setzt `scripts/setup-db.ts` (AUDIT_INSERT_TABLES). Die Liste hier
// ist bewusst eine zweite, unabhängige Aufschreibung: sie muss geändert werden,
// wenn jemand die Grants aufweicht.

import { describe, it, expect } from 'vitest';
import { auditDb, db } from '../../db/index.js';

const AUDIT_INSERT_TABLES = [
  'audit_log',
  'email_log',
  'order_item_modifiers',
  'order_item_removals',
  'product_price_history',
  'z_reports',
];

// SHOW GRANTS ohne FOR-Klausel zeigt die Rechte des verbundenen Users selbst —
// dafür braucht auditDb keine Sonderrechte. `TO PUBLIC` fliegt raus: MariaDB
// listet dort serverweite Defaults (u.a. auf der `test`-Datenbank), die nicht
// diesem User gehören und über die dieses Projekt nicht entscheidet.
async function auditGrants(): Promise<string[]> {
  const [rows] = await auditDb.query<any[]>('SHOW GRANTS');
  return rows
    .map((r) => String(Object.values(r)[0]))
    .filter((g) => !/\bTO\s+PUBLIC\b/i.test(g));
}

describe('DB-Grants: audit_insert_user', () => {
  it('hat INSERT nur auf den Audit-Tabellen — kein datenbankweites INSERT', async () => {
    const grants = await auditGrants();

    const dbWide = grants.filter((g) => /\bINSERT\b/.test(g) && /\.\s*\*/.test(g));
    expect(dbWide, `datenbankweiter INSERT-Grant gefunden: ${dbWide.join(' | ')}`).toEqual([]);

    const granted = grants
      .map((g) => /ON\s+`[^`]+`\.`([^`]+)`/.exec(g)?.[1])
      .filter((t): t is string => Boolean(t))
      .sort();
    expect(granted).toEqual(AUDIT_INSERT_TABLES);
  });

  it('hat außer INSERT (und USAGE) keine Rechte', async () => {
    const grants = await auditGrants();
    for (const g of grants) {
      const privileges = /^GRANT\s+(.+?)\s+ON\s/.exec(g)?.[1] ?? '';
      for (const p of privileges.split(',').map((s) => s.trim())) {
        expect(['INSERT', 'USAGE'], `unerwartetes Recht in: ${g}`).toContain(p);
      }
    }
  });

  it('kann nicht in eine Nicht-Audit-Tabelle schreiben (Finanztabellen bleiben tabu)', async () => {
    const [t] = await db.execute<any>(
      `INSERT INTO tenants (name, address, plan, subscription_status)
       VALUES ('Grant GmbH', 'Str. 1, Berlin', 'starter', 'active')`
    );
    const tenantId = t.insertId as number;

    await expect(
      auditDb.execute(
        `INSERT INTO orders (tenant_id, status, opened_by_user_id) VALUES (?, 'open', 1)`,
        [tenantId]
      )
    ).rejects.toMatchObject({ code: 'ER_TABLEACCESS_DENIED_ERROR' });
  });
});

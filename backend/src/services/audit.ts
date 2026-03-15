import { auditDb } from '../db/index.js';

interface AuditEntry {
  tenantId:   number;
  userId:     number | null;
  action:     string;        // z.B. 'user.deleted', 'device.revoked'
  entityType: string;        // z.B. 'user', 'device'
  entityId:   number;
  diff?:      { old?: unknown; new?: unknown };
  ipAddress?: string;
  deviceId?:  number;
}

// audit_insert_user hat NUR INSERT-Rechte auf audit_log (GoBD)
export async function writeAuditLog(entry: AuditEntry): Promise<void> {
  await auditDb.execute(
    `INSERT INTO audit_log
       (tenant_id, user_id, action, entity_type, entity_id, diff_json, ip_address, device_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      entry.tenantId,
      entry.userId ?? null,
      entry.action,
      entry.entityType,
      entry.entityId,
      entry.diff ? JSON.stringify(entry.diff) : null,
      entry.ipAddress ?? null,
      entry.deviceId ?? null,
    ]
  );
}

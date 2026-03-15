Debugge die Offline-Queue des Kassensystems. Ich beschreibe das Problem (z.B. "stuck pending entries", "idempotency conflict", "TSE-Timeout"), du führst eine strukturierte Diagnose durch.

**Schritt-für-Schritt-Diagnose:**

### 1. Queue-Status prüfen
```sql
-- Pending/failed Einträge der letzten 24h
SELECT id, operation_type, status, retry_count, error_message, created_at, synced_at
FROM offline_queue
WHERE tenant_id = ? AND status IN ('pending', 'processing', 'failed')
  AND created_at > NOW() - INTERVAL 24 HOUR
ORDER BY created_at DESC;
```

### 2. Idempotency-Duplikate prüfen
```sql
-- Doppelte idempotency_keys (sollte nie vorkommen)
SELECT idempotency_key, COUNT(*) as cnt
FROM offline_queue
WHERE tenant_id = ?
GROUP BY idempotency_key HAVING cnt > 1;
```

### 3. Fiskaly-TX-Status direkt abfragen (bei TSE-Timeouts)
- **Immer zuerst GET /tx/{tx_id} prüfen** bevor ein neuer Request gesendet wird
- Falls TX existiert und `state = ACTIVE`: mit FINISH abschließen (idempotency_key wiederverwenden)
- Falls TX nicht existiert: neu anlegen
- Falls TX `state = FINISHED`: bereits erfolgreich — `offline_queue.status = 'synced'` setzen

### 4. Stuck-Entries (status = 'processing' > 5 Min)
```sql
-- Entries die wahrscheinlich durch Crash hängengeblieben sind
SELECT * FROM offline_queue
WHERE status = 'processing'
  AND updated_at < NOW() - INTERVAL 5 MINUTE;
-- Fix: status zurück auf 'pending' setzen (retry loop greift dann)
```

### 5. TSE-Ausfall dokumentieren
```sql
-- Aktive Ausfälle prüfen
SELECT * FROM tse_outages WHERE ended_at IS NULL;

-- Ausfall beenden (UPDATE erlaubt auf tse_outages.ended_at)
UPDATE tse_outages SET ended_at = NOW() WHERE id = ?;
```

**Kritische Regeln:**
- `offline_queue.status` darf aktualisiert werden (erlaubtes UPDATE-Feld)
- Niemals Einträge aus `offline_queue` löschen — append-only für Audit-Trail
- Bei jedem Recovery-Versuch: idempotency_key aus dem Original-Eintrag wiederverwenden
- `tse_outages.ended_at` und `.notified_at` dürfen gesetzt werden

**Format der Eingabe:** Beschreibe das Problem, z.B.:
"3 Einträge stecken seit 10 Minuten auf 'processing' fest"
"TSE-Timeout beim Payment — weiß nicht ob TX bei Fiskaly angelegt wurde"

import { Connection } from 'mysql2/promise';

// Zwei Tabellen mit bewusst getrennten Rollen (OFFEN.md §5):
//
//   email_queue — OPERATIV. Retry-Zustand einer noch nicht zugestellten Mail.
//                 status/attempts/next_attempt_at/last_error/… dürfen per UPDATE
//                 fortgeschrieben werden (Muster: offline_queue). Nach Erfolg
//                 werden subject/html/text genullt (DSGVO: kein Dauerspeicher
//                 für Empfängerinhalte).
//
//   email_log   — NACHWEIS. INSERT-only über audit_insert_user, analog audit_log.
//                 Bei KassenSichV-Meldemails (TSE-Ausfall > 48h) muss belegbar
//                 sein, DASS und WANN gesendet wurde — deshalb unveränderlich und
//                 getrennt von der Queue, deren Zeilen sich noch ändern dürfen.
export async function up(db: Connection): Promise<void> {
  await db.execute(`
    CREATE TABLE email_queue (
      id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id             INT UNSIGNED  NULL,    -- NULL: System-Mail ohne Tenant-Bezug
      template              VARCHAR(50)   NOT NULL,
      recipient             VARCHAR(255)  NOT NULL,
      reply_to              VARCHAR(255)  NULL,
      subject               VARCHAR(255)  NULL,    -- nach Versand genullt (DSGVO)
      body_html             MEDIUMTEXT    NULL,    -- nach Versand genullt
      body_text             MEDIUMTEXT    NULL,    -- nach Versand genullt
      idempotency_key       VARCHAR(120)  NOT NULL, -- verhindert Doppelversand (Cron läuft mehrfach)
      status                ENUM('pending','processing','sent','failed') NOT NULL DEFAULT 'pending',
      attempts              INT UNSIGNED  NOT NULL DEFAULT 0,
      max_attempts          INT UNSIGNED  NOT NULL DEFAULT 6,
      last_error            TEXT          NULL,
      next_attempt_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      processing_started_at DATETIME      NULL,    -- Claim-Zeitpunkt (Stuck-Reset, wie V006)
      created_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      sent_at               DATETIME      NULL,
      UNIQUE KEY uq_email_queue_idempotency (idempotency_key),
      KEY idx_email_queue_due (status, next_attempt_at),
      CONSTRAINT fk_email_queue_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD/KassenSichV: NUR INSERT, kein UPDATE/DELETE — Versandnachweis
    -- DB-User: audit_insert_user (INSERT-only per GRANT)
    CREATE TABLE email_log (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id           INT UNSIGNED  NULL,
      template            VARCHAR(50)   NOT NULL,
      recipient           VARCHAR(255)  NOT NULL,
      subject             VARCHAR(255)  NOT NULL,
      provider_message_id VARCHAR(255)  NULL,   -- Resend-ID; NULL im Dry-Run (kein Key)
      sent_at             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      KEY idx_email_log_tenant (tenant_id, sent_at),
      KEY idx_email_log_template (template, sent_at),
      CONSTRAINT fk_email_log_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

export async function down(db: Connection): Promise<void> {
  await db.execute('DROP TABLE IF EXISTS email_log');
  await db.execute('DROP TABLE IF EXISTS email_queue');
}

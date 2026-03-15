import { Connection } from 'mysql2/promise';

export async function up(db: Connection): Promise<void> {

  // ─── Tenants & Users ────────────────────────────────────────────────────────

  await db.execute(`
    CREATE TABLE tenants (
      id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      name                    VARCHAR(255)  NOT NULL,
      address                 TEXT          NOT NULL,     -- Pflichtfeld auf Bon (§14 UStG)
      vat_id                  VARCHAR(50)   NULL,         -- USt-IdNr. (Pflichtfeld auf Bon)
      tax_number              VARCHAR(50)   NULL,         -- Steuernummer (Pflichtfeld auf Bon)
      fiskaly_tss_id          VARCHAR(255)  NULL,         -- pro Tenant eine eigene TSS
      stripe_customer_id      VARCHAR(255)  NULL,
      stripe_subscription_id  VARCHAR(255)  NULL,
      plan                    ENUM('starter','pro','business') NOT NULL DEFAULT 'starter',
      subscription_status     ENUM('active','past_due','cancelled') NOT NULL DEFAULT 'active',
      data_retention_until    DATE          NULL,         -- GoBD: 10 Jahre nach letzter Transaktion/Kündigung
      created_at              DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE users (
      id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id     INT UNSIGNED NOT NULL,
      name          VARCHAR(255) NOT NULL,
      email         VARCHAR(255) NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      role          ENUM('owner','manager','staff') NOT NULL DEFAULT 'staff',
      pin_hash      VARCHAR(255) NULL,   -- 4-stellige PIN für schnellen iPad-Wechsel
      is_active     BOOLEAN      NOT NULL DEFAULT TRUE,  -- soft delete
      created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_users_email_tenant (tenant_id, email),
      CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE devices (
      id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id         INT UNSIGNED  NOT NULL,
      name              VARCHAR(255)  NOT NULL,
      device_token_hash VARCHAR(255)  NOT NULL,  -- nur Hash in DB, Klartext nur bei Ausstellung
      tse_client_id     VARCHAR(255)  NULL,       -- Fiskaly Client-ID (jedes Gerät = eigener Client)
      min_app_version   VARCHAR(20)   NULL,       -- versionMiddleware: 426 wenn App veraltet
      is_revoked        BOOLEAN       NOT NULL DEFAULT FALSE,
      last_seen_at      DATETIME      NULL,
      created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_devices_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Produkte ───────────────────────────────────────────────────────────────

  await db.execute(`
    CREATE TABLE product_categories (
      id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id  INT UNSIGNED NOT NULL,
      name       VARCHAR(255) NOT NULL,
      color      VARCHAR(7)   NULL,        -- Hex-Farbe für UI
      sort_order INT          NOT NULL DEFAULT 0,
      is_active  BOOLEAN      NOT NULL DEFAULT TRUE,
      CONSTRAINT fk_product_categories_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE products (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id           INT UNSIGNED NOT NULL,
      category_id         INT UNSIGNED NULL,
      name                VARCHAR(255) NOT NULL,
      -- GoBD: price_cents + vat_rate_* sind IMMUTABLE → Änderungen nur via product_price_history
      price_cents         INT          NOT NULL,
      vat_rate_inhouse    ENUM('7','19') NOT NULL DEFAULT '19',
      vat_rate_takeaway   ENUM('7','19') NOT NULL DEFAULT '19',  -- Phase 4+, vorerst = vat_rate_inhouse
      is_active           BOOLEAN      NOT NULL DEFAULT TRUE,    -- soft delete (darf geupdated werden)
      created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      CONSTRAINT fk_products_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
      CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES product_categories(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE
    -- DB-User: audit_insert_user (INSERT-only)
    CREATE TABLE product_price_history (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      product_id          INT UNSIGNED  NOT NULL,
      tenant_id           INT UNSIGNED  NOT NULL,
      price_cents         INT           NOT NULL,
      vat_rate_inhouse    ENUM('7','19') NOT NULL,
      vat_rate_takeaway   ENUM('7','19') NOT NULL,
      changed_by_user_id  INT UNSIGNED  NOT NULL,
      valid_from          DATETIME      NOT NULL,
      created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_price_history_product FOREIGN KEY (product_id) REFERENCES products(id),
      CONSTRAINT fk_price_history_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE product_modifier_groups (
      id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id    INT UNSIGNED NOT NULL,
      product_id   INT UNSIGNED NULL,   -- NULL wenn category_id gesetzt
      category_id  INT UNSIGNED NULL,   -- Gruppe gilt für alle Produkte dieser Kategorie
      name         VARCHAR(255) NOT NULL,
      is_required  BOOLEAN      NOT NULL DEFAULT FALSE,
      min_selections INT        NOT NULL DEFAULT 0,
      max_selections INT        NULL,   -- NULL = unbegrenzt, 1 = Einzelauswahl
      is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
      sort_order   INT          NOT NULL DEFAULT 0,
      -- Entweder product_id ODER category_id gesetzt, nicht beides
      CONSTRAINT chk_modifier_group_target CHECK (
        (product_id IS NOT NULL AND category_id IS NULL) OR
        (product_id IS NULL AND category_id IS NOT NULL)
      ),
      CONSTRAINT fk_modifier_group_tenant   FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
      CONSTRAINT fk_modifier_group_product  FOREIGN KEY (product_id)  REFERENCES products(id),
      CONSTRAINT fk_modifier_group_category FOREIGN KEY (category_id) REFERENCES product_categories(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE product_modifier_options (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      modifier_group_id   INT UNSIGNED NOT NULL,
      tenant_id           INT UNSIGNED NOT NULL,
      name                VARCHAR(255) NOT NULL,
      price_delta_cents   INT          NOT NULL DEFAULT 0,  -- 0 = inklusive, 200 = +2,00€
      is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
      sort_order          INT          NOT NULL DEFAULT 0,
      CONSTRAINT fk_modifier_option_group  FOREIGN KEY (modifier_group_id) REFERENCES product_modifier_groups(id),
      CONSTRAINT fk_modifier_option_tenant FOREIGN KEY (tenant_id)         REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Tische & Zonen ─────────────────────────────────────────────────────────

  await db.execute(`
    CREATE TABLE zones (
      id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id  INT UNSIGNED NOT NULL,
      name       VARCHAR(255) NOT NULL,
      sort_order INT          NOT NULL DEFAULT 0,
      CONSTRAINT fk_zones_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE tables (
      id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id  INT UNSIGNED NOT NULL,
      zone_id    INT UNSIGNED NULL,
      name       VARCHAR(255) NOT NULL,
      is_active  BOOLEAN      NOT NULL DEFAULT TRUE,
      CONSTRAINT fk_tables_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
      CONSTRAINT fk_tables_zone   FOREIGN KEY (zone_id)   REFERENCES zones(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Bon-Nummern-Sequenz (GoBD-konform, atomar) ──────────────────────────

  await db.execute(`
    -- KassenSichV: fortlaufend, niemals zurücksetzen
    -- Zugriff NUR via: SELECT ... FOR UPDATE → Increment → Commit
    CREATE TABLE receipt_sequences (
      tenant_id   INT UNSIGNED NOT NULL PRIMARY KEY,
      last_number INT          NOT NULL DEFAULT 0,
      CONSTRAINT fk_receipt_sequences_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Kassensitzungen / Schichten (GoBD: Z-Bericht-Grundlage) ────────────

  await db.execute(`
    CREATE TABLE cash_register_sessions (
      id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id             INT UNSIGNED NOT NULL,
      device_id             INT UNSIGNED NOT NULL,
      opened_by_user_id     INT UNSIGNED NOT NULL,
      opened_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      closed_by_user_id     INT UNSIGNED NULL,
      closed_at             DATETIME     NULL,
      opening_cash_cents    INT          NOT NULL,  -- Anfangsbestand (manuell gezählt)
      closing_cash_cents    INT          NULL,       -- Endbestand (manuell gezählt)
      expected_cash_cents   INT          NULL,       -- berechnet: Anfang + Einnahmen + Einlagen - Entnahmen
      difference_cents      INT          NULL,       -- Abweichung (Soll - Ist)
      status                ENUM('open','closed') NOT NULL DEFAULT 'open',
      created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      -- GoBD: täglicher Abschluss — Cron-Job warnt bei >24h offener Session
      CONSTRAINT fk_sessions_tenant          FOREIGN KEY (tenant_id)         REFERENCES tenants(id),
      CONSTRAINT fk_sessions_device          FOREIGN KEY (device_id)         REFERENCES devices(id),
      CONSTRAINT fk_sessions_opened_by_user  FOREIGN KEY (opened_by_user_id) REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE — Unveränderlichkeit des Z-Berichts
    -- DB-User: audit_insert_user (INSERT-only)
    CREATE TABLE z_reports (
      id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      session_id   INT UNSIGNED NOT NULL,
      tenant_id    INT UNSIGNED NOT NULL,
      report_json  JSON         NOT NULL,  -- unveränderlicher Snapshot
      created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_z_reports_session FOREIGN KEY (session_id) REFERENCES cash_register_sessions(id),
      CONSTRAINT fk_z_reports_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE cash_movements (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      session_id          INT UNSIGNED NOT NULL,
      tenant_id           INT UNSIGNED NOT NULL,
      type                ENUM('deposit','withdrawal') NOT NULL,
      amount_cents        INT          NOT NULL,
      reason              VARCHAR(500) NOT NULL,  -- Pflichtfeld: z.B. "Wechselgeld einlegen"
      created_by_user_id  INT UNSIGNED NOT NULL,
      created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_cash_movements_session FOREIGN KEY (session_id) REFERENCES cash_register_sessions(id),
      CONSTRAINT fk_cash_movements_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Bestellungen (GoBD: nie löschen) ───────────────────────────────────

  await db.execute(`
    -- GoBD: NUR INSERT auf Finanzdaten, kein UPDATE/DELETE
    CREATE TABLE orders (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id           INT UNSIGNED NOT NULL,
      table_id            INT UNSIGNED NULL,   -- NULL = Schnellverkauf/Theke ohne Tisch
      session_id          INT UNSIGNED NOT NULL,
      is_takeaway         BOOLEAN      NOT NULL DEFAULT FALSE,  -- Phase 4+, vorerst immer FALSE
      opened_by_user_id   INT UNSIGNED NOT NULL,
      status              ENUM('open','paid','cancelled') NOT NULL DEFAULT 'open',
      created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      closed_at           DATETIME     NULL,   -- KassenSichV: Transaktionsende dokumentieren
      CONSTRAINT fk_orders_tenant  FOREIGN KEY (tenant_id)         REFERENCES tenants(id),
      CONSTRAINT fk_orders_table   FOREIGN KEY (table_id)          REFERENCES tables(id),
      CONSTRAINT fk_orders_session FOREIGN KEY (session_id)        REFERENCES cash_register_sessions(id),
      CONSTRAINT fk_orders_user    FOREIGN KEY (opened_by_user_id) REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE — Stornierungen über cancellations-Tabelle
    CREATE TABLE order_items (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      order_id            INT UNSIGNED  NOT NULL,
      product_id          INT UNSIGNED  NOT NULL,
      product_name        VARCHAR(255)  NOT NULL,  -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      product_price_cents INT           NOT NULL,  -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      vat_rate            ENUM('7','19') NOT NULL, -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      quantity            INT           NOT NULL DEFAULT 1,
      subtotal_cents      INT           NOT NULL,  -- (product_price_cents + SUM(modifier_deltas)) × quantity - discount_cents
      discount_cents      INT           NOT NULL DEFAULT 0,
      discount_reason     VARCHAR(500)  NULL,      -- Pflichtfeld wenn discount_cents > 0 (GoBD)
      added_by_user_id    INT UNSIGNED  NOT NULL,
      created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_order_items_order   FOREIGN KEY (order_id)         REFERENCES orders(id),
      CONSTRAINT fk_order_items_product FOREIGN KEY (product_id)       REFERENCES products(id),
      CONSTRAINT fk_order_items_user    FOREIGN KEY (added_by_user_id) REFERENCES users(id),
      CONSTRAINT chk_discount_reason    CHECK (discount_cents = 0 OR discount_reason IS NOT NULL)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE
    -- DB-User: audit_insert_user (INSERT-only)
    CREATE TABLE order_item_modifiers (
      id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      order_item_id        INT UNSIGNED NOT NULL,
      modifier_option_id   INT UNSIGNED NOT NULL,
      option_name          VARCHAR(255) NOT NULL,  -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      price_delta_cents    INT          NOT NULL,  -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      created_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_order_item_modifiers_item   FOREIGN KEY (order_item_id)      REFERENCES order_items(id),
      CONSTRAINT fk_order_item_modifiers_option FOREIGN KEY (modifier_option_id) REFERENCES product_modifier_options(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Zahlungen & Bons (TSE) ──────────────────────────────────────────────

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE
    -- KassenSichV: fortlaufend, niemals zurücksetzen
    CREATE TABLE receipts (
      id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id               INT UNSIGNED  NOT NULL,
      order_id                INT UNSIGNED  NOT NULL,
      session_id              INT UNSIGNED  NOT NULL,
      receipt_number          INT           NOT NULL,  -- KassenSichV: fortlaufend, niemals zurücksetzen
      status                  ENUM('active','voided') NOT NULL DEFAULT 'voided',
      void_reason             VARCHAR(500)  NULL,      -- wenn status='voided' (Lücken-Dokumentation GoBD)
      is_split_receipt        BOOLEAN       NOT NULL DEFAULT FALSE,
      split_group_id          INT UNSIGNED  NULL,      -- gemeinsame ID aller Split-Bons einer Order
      -- § 6 Abs. 1 Nr. 6 KassenSichV: Seriennummer des Aufzeichnungssystems
      device_id               INT UNSIGNED  NOT NULL,  -- SNAPSHOT: welches iPad
      device_name             VARCHAR(255)  NOT NULL,  -- SNAPSHOT: wird zum Zeitpunkt der Erstellung gesetzt
      -- TSE-Daten (Pflichtfelder § 6 KassenSichV)
      tse_transaction_id      VARCHAR(255)  NULL,
      tse_serial_number       VARCHAR(255)  NULL,
      tse_signature           TEXT          NULL,
      tse_counter             INT           NULL,
      tse_transaction_start   DATETIME(3)   NULL,
      tse_transaction_end     DATETIME(3)   NULL,
      tse_pending             BOOLEAN       NOT NULL DEFAULT FALSE,
      -- MwSt-Aufschlüsselung (§ 14 UStG)
      vat_7_net_cents         INT           NOT NULL DEFAULT 0,
      vat_7_tax_cents         INT           NOT NULL DEFAULT 0,
      vat_19_net_cents        INT           NOT NULL DEFAULT 0,
      vat_19_tax_cents        INT           NOT NULL DEFAULT 0,
      total_gross_cents       INT           NOT NULL DEFAULT 0,
      tip_cents               INT           NOT NULL DEFAULT 0,  -- Phase 3+, immer 0 bis dahin
      is_takeaway             BOOLEAN       NOT NULL DEFAULT FALSE,  -- Phase 4+
      -- SNAPSHOT: wird NUR beim finalen status='active' befüllt, danach kein UPDATE
      raw_receipt_json        JSON          NULL,
      created_at              DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_receipts_number_tenant (tenant_id, receipt_number),
      CONSTRAINT fk_receipts_tenant  FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
      CONSTRAINT fk_receipts_order   FOREIGN KEY (order_id)   REFERENCES orders(id),
      CONSTRAINT fk_receipts_session FOREIGN KEY (session_id) REFERENCES cash_register_sessions(id),
      CONSTRAINT fk_receipts_device  FOREIGN KEY (device_id)  REFERENCES devices(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE
    CREATE TABLE payments (
      id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      order_id          INT UNSIGNED NOT NULL,
      receipt_id        INT UNSIGNED NOT NULL,
      method            ENUM('cash','card') NOT NULL,
      amount_cents      INT          NOT NULL,
      tip_cents         INT          NOT NULL DEFAULT 0,  -- Phase 3+, kein MwSt
      paid_at           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      paid_by_user_id   INT UNSIGNED NOT NULL,
      CONSTRAINT fk_payments_order   FOREIGN KEY (order_id)        REFERENCES orders(id),
      CONSTRAINT fk_payments_receipt FOREIGN KEY (receipt_id)      REFERENCES receipts(id),
      CONSTRAINT fk_payments_user    FOREIGN KEY (paid_by_user_id) REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await db.execute(`
    CREATE TABLE payment_splits (
      id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      order_id            INT UNSIGNED NOT NULL,
      receipt_id          INT UNSIGNED NOT NULL,  -- eigener Bon pro Split
      items_json          JSON         NOT NULL,  -- welche order_item_ids in diesem Split
      total_cents         INT          NOT NULL,
      created_by_user_id  INT UNSIGNED NOT NULL,
      created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_payment_splits_order   FOREIGN KEY (order_id)            REFERENCES orders(id),
      CONSTRAINT fk_payment_splits_receipt FOREIGN KEY (receipt_id)          REFERENCES receipts(id),
      CONSTRAINT fk_payment_splits_user    FOREIGN KEY (created_by_user_id)  REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Storno (GoBD: Gegenbuchung, nie löschen) ───────────────────────────

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE
    CREATE TABLE cancellations (
      id                        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      original_receipt_id       INT UNSIGNED NOT NULL,
      original_receipt_number   INT          NOT NULL,  -- denormalisiert für Bon-Ausdruck
      cancellation_receipt_id   INT UNSIGNED NOT NULL,  -- neuer Storno-Bon (negative TSE-Transaktion)
      cancelled_by_user_id      INT UNSIGNED NOT NULL,
      reason                    TEXT         NOT NULL,  -- Pflichtfeld (GoBD)
      created_at                DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_cancellations_original     FOREIGN KEY (original_receipt_id)     REFERENCES receipts(id),
      CONSTRAINT fk_cancellations_cancellation FOREIGN KEY (cancellation_receipt_id) REFERENCES receipts(id),
      CONSTRAINT fk_cancellations_user         FOREIGN KEY (cancelled_by_user_id)    REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Offline-Queue (TSE-Signatur nachholen) ──────────────────────────────

  await db.execute(`
    CREATE TABLE offline_queue (
      id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id        INT UNSIGNED  NOT NULL,
      device_id        INT UNSIGNED  NOT NULL,
      order_id         INT UNSIGNED  NOT NULL,
      payload_json     JSON          NOT NULL,
      idempotency_key  VARCHAR(36)   NOT NULL,  -- UUID, verhindert doppelte TSE-Transaktion bei Timeout
      status           ENUM('pending','processing','completed','failed') NOT NULL DEFAULT 'pending',
      retry_count      INT           NOT NULL DEFAULT 0,
      error_message    TEXT          NULL,
      created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      synced_at        DATETIME      NULL,
      UNIQUE KEY uq_offline_queue_idempotency (idempotency_key),
      CONSTRAINT fk_offline_queue_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
      CONSTRAINT fk_offline_queue_device FOREIGN KEY (device_id) REFERENCES devices(id),
      CONSTRAINT fk_offline_queue_order  FOREIGN KEY (order_id)  REFERENCES orders(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Audit-Log (GoBD: unveränderlich) ───────────────────────────────────

  await db.execute(`
    -- GoBD: NUR INSERT, kein UPDATE/DELETE — Unveränderlichkeit des Audit-Logs
    -- DB-User: audit_insert_user (INSERT-only per GRANT)
    CREATE TABLE audit_log (
      id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id    INT UNSIGNED  NOT NULL,
      user_id      INT UNSIGNED  NULL,    -- NULL bei System-Aktionen
      action       VARCHAR(100)  NOT NULL,  -- z.B. 'order.item_removed', 'receipt.created'
      entity_type  VARCHAR(50)   NOT NULL,
      entity_id    INT UNSIGNED  NOT NULL,
      diff_json    JSON          NULL,      -- old/new Werte
      ip_address   VARCHAR(45)   NULL,      -- IPv4 oder IPv6
      device_id    INT UNSIGNED  NULL,      -- von welchem Gerät
      created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_audit_log_tenant_created (tenant_id, created_at),
      INDEX idx_audit_log_entity (entity_type, entity_id),
      CONSTRAINT fk_audit_log_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── Stripe Events ───────────────────────────────────────────────────────

  await db.execute(`
    CREATE TABLE subscription_events (
      id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id        INT UNSIGNED  NULL,   -- NULL wenn Tenant noch nicht angelegt (z.B. checkout)
      stripe_event_id  VARCHAR(255)  NOT NULL,
      event_type       VARCHAR(100)  NOT NULL,
      payload_json     JSON          NOT NULL,
      processed        BOOLEAN       NOT NULL DEFAULT FALSE,
      created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_subscription_events_stripe_id (stripe_event_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // ─── TSE-Ausfall Monitoring ──────────────────────────────────────────────

  await db.execute(`
    CREATE TABLE tse_outages (
      id                       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id                INT UNSIGNED NOT NULL,
      device_id                INT UNSIGNED NOT NULL,
      started_at               DATETIME     NOT NULL,
      ended_at                 DATETIME     NULL,
      notified_at              DATETIME     NULL,      -- wann Tenant-Owner benachrichtigt wurde
      reported_to_finanzamt    BOOLEAN      NOT NULL DEFAULT FALSE,  -- Pflicht nach 48h Ausfall
      created_at               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT fk_tse_outages_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
      CONSTRAINT fk_tse_outages_device FOREIGN KEY (device_id) REFERENCES devices(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

}

export async function down(db: Connection): Promise<void> {
  // GoBD: down() ist VERBOTEN in Produktion — Finanzdaten dürfen nicht gelöscht werden
  if (process.env['NODE_ENV'] === 'production') {
    throw new Error('Migration down() darf in Produktion nicht ausgeführt werden (GoBD-Pflicht: keine Löschung von Finanzdaten).');
  }
  // Reihenfolge: abhängige Tabellen zuerst
  await db.execute('DROP TABLE IF EXISTS tse_outages');
  await db.execute('DROP TABLE IF EXISTS subscription_events');
  await db.execute('DROP TABLE IF EXISTS audit_log');
  await db.execute('DROP TABLE IF EXISTS offline_queue');
  await db.execute('DROP TABLE IF EXISTS cancellations');
  await db.execute('DROP TABLE IF EXISTS payment_splits');
  await db.execute('DROP TABLE IF EXISTS payments');
  await db.execute('DROP TABLE IF EXISTS receipts');
  await db.execute('DROP TABLE IF EXISTS order_item_modifiers');
  await db.execute('DROP TABLE IF EXISTS order_items');
  await db.execute('DROP TABLE IF EXISTS orders');
  await db.execute('DROP TABLE IF EXISTS cash_movements');
  await db.execute('DROP TABLE IF EXISTS z_reports');
  await db.execute('DROP TABLE IF EXISTS cash_register_sessions');
  await db.execute('DROP TABLE IF EXISTS receipt_sequences');
  await db.execute('DROP TABLE IF EXISTS tables');
  await db.execute('DROP TABLE IF EXISTS zones');
  await db.execute('DROP TABLE IF EXISTS product_modifier_options');
  await db.execute('DROP TABLE IF EXISTS product_modifier_groups');
  await db.execute('DROP TABLE IF EXISTS product_price_history');
  await db.execute('DROP TABLE IF EXISTS products');
  await db.execute('DROP TABLE IF EXISTS product_categories');
  await db.execute('DROP TABLE IF EXISTS devices');
  await db.execute('DROP TABLE IF EXISTS users');
  await db.execute('DROP TABLE IF EXISTS tenants');
}

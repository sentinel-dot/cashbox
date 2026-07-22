import { Connection } from 'mysql2/promise';

// S08 (OFFEN.md B3): Passwort-Reset per Mail-Link.
//
// Warum SHA-256 statt bcrypt für den Token-Hash: Der Token ist kein Passwort,
// sondern 32 zufällige Bytes — es gibt nichts zu erraten, also braucht es keinen
// Key-Stretching-Faktor. Dafür ist ein schneller Hash indexierbar, und genau das
// brauchen wir: Der eingehende Link wird per Gleichheits-Lookup gefunden, nicht
// per Tabellenscan mit bcrypt.compare über alle offenen Tokens. Dasselbe Muster
// nutzt `devices.device_token_hash` (SHA2 in der DB) bereits.
//
// `used_at` statt DELETE: Ein verbrauchter Token bleibt nachweisbar (wann wurde
// zurückgesetzt), und ein zweiter Klick auf denselben Link läuft in eine klare
// „schon verwendet"-Meldung statt in „unbekannter Token".
export async function up(db: Connection): Promise<void> {
  await db.execute(`
    CREATE TABLE password_reset_tokens (
      id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      tenant_id  INT UNSIGNED NOT NULL,
      user_id    INT UNSIGNED NOT NULL,
      token_hash CHAR(64)     NOT NULL COMMENT 'SHA2(klartext, 256) als Hex — Klartext existiert nur in der Mail',
      expires_at DATETIME     NOT NULL,
      used_at    DATETIME     NULL COMMENT 'Einmal-Token: gesetzt beim Einlösen ODER beim Entwerten durch einen neueren Token',
      created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY uq_prt_token (token_hash),
      KEY idx_prt_user (user_id, created_at),
      CONSTRAINT fk_prt_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
      CONSTRAINT fk_prt_user   FOREIGN KEY (user_id)   REFERENCES users(id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  // Ein Passwortwechsel muss laufende Sitzungen beenden — sonst überlebt ein
  // gestohlenes Refresh-Token (bis zu SESSION_MAX_HOURS) genau den Reset, der
  // es aussperren sollte. `/auth/refresh` vergleicht den `session_start`-Claim
  // gegen diesen Zeitpunkt. NULL = nie geändert (Bestandsnutzer).
  await db.execute(
    `ALTER TABLE users
     ADD COLUMN password_changed_at DATETIME NULL
       COMMENT 'Reset/Änderung entwertet ältere Refresh-Tokens (S08)' AFTER password_hash`
  );
}

export async function down(db: Connection): Promise<void> {
  await db.execute('ALTER TABLE users DROP COLUMN password_changed_at');
  await db.execute('DROP TABLE IF EXISTS password_reset_tokens');
}

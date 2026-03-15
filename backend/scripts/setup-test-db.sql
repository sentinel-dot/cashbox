-- Schritt 1: Testdatenbank + DB-User anlegen (vor Migration ausführen)
-- Ausführen mit: sudo mysql < backend/scripts/setup-test-db.sql

CREATE DATABASE IF NOT EXISTS cashbox_test
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- app_user: SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER (ALTER für Migrations nötig)
CREATE USER IF NOT EXISTS 'app_user_test'@'localhost' IDENTIFIED BY 'test_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER ON cashbox_test.* TO 'app_user_test'@'localhost';

-- audit_insert_user: INSERT only auf cashbox_test.*
-- Nach Migration via setup-test-grants.sql auf spezifische Tabellen einschränken
CREATE USER IF NOT EXISTS 'audit_insert_user_test'@'localhost' IDENTIFIED BY 'test_password';
GRANT INSERT ON cashbox_test.* TO 'audit_insert_user_test'@'localhost';

-- app_readonly: SELECT only
CREATE USER IF NOT EXISTS 'app_readonly_test'@'localhost' IDENTIFIED BY 'test_password';
GRANT SELECT ON cashbox_test.* TO 'app_readonly_test'@'localhost';

FLUSH PRIVILEGES;

SELECT 'Test-DB und User erfolgreich angelegt. Jetzt: npm run migrate:test' AS status;

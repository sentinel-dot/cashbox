import dotenv from 'dotenv';
import path from 'path';
import { afterEach } from 'vitest';

// Vor allen Imports: .env.test laden — CWD ist beim Testlauf das backend/-Verzeichnis.
// override: true stellt sicher dass diese Werte nicht von späteren dotenv.config()-Aufrufen
// (z.B. in db/index.ts oder app.ts) überschrieben werden.
dotenv.config({ path: path.resolve(process.cwd(), '.env.test'), override: true });

afterEach(async () => {
  const { cleanTestDB } = await import('./testHelpers.js');
  await cleanTestDB();
});

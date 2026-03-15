import dotenv from 'dotenv';
import path from 'path';
import { afterEach, beforeAll } from 'vitest';

// .env zuerst (Fiskaly/Stripe-Creds), dann .env.test mit override:true (Test-DB überschreibt Prod-DB).
// .env.test enthält keine Fiskaly-Vars mehr → Fiskaly-Creds aus .env bleiben erhalten.
dotenv.config({ path: path.resolve(process.cwd(), '.env'), override: true });
dotenv.config({ path: path.resolve(process.cwd(), '.env.test'), override: true });

beforeAll(() => {
  if (!process.env['FISKALY_API_KEY'] || !process.env['FISKALY_API_SECRET']) {
    throw new Error(
      'FISKALY_API_KEY und FISKALY_API_SECRET müssen in .env gesetzt sein für externe Tests.'
    );
  }
  if (!process.env['FISKALY_TSS_ID'] || !process.env['FISKALY_CLIENT_ID']) {
    throw new Error(
      'FISKALY_TSS_ID und FISKALY_CLIENT_ID müssen in .env gesetzt sein.\n' +
      'npx tsx scripts/fiskaly-setup.ts → SQL ausführen → IDs in .env eintragen.'
    );
  }
});

afterEach(async () => {
  const { cleanTestDB } = await import('../testHelpers.js');
  await cleanTestDB();
});

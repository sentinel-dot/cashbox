import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    env: { NODE_ENV: 'test' },
    setupFiles: ['./src/__tests__/setup.ts'],
    // Alle Test-Dateien sequentiell — Integrationstests teilen dieselbe DB
    singleFork: true,
    fileParallelism: false,
    testTimeout: 30_000,
  },
});

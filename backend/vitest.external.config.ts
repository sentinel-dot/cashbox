import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    env: { NODE_ENV: 'test' },
    setupFiles: ['./src/__tests__/external/setup.ts'],
    singleFork: true,
    fileParallelism: false,
    // TSE-API-Aufrufe können mehrere Sekunden dauern
    testTimeout: 60_000,
    hookTimeout: 30_000,
  },
});

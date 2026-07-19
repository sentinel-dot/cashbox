import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createShutdown, type ShutdownDeps } from '../../shutdown.js';

// REQ-OPS-001 (UC-OPS-01): Der Prozess fährt kontrolliert herunter — laufende
// Requests werden zu Ende geführt, bevor DB-Pools schließen. Ein SIGTERM mitten
// in payOrder darf keine angefangene Bon-Transaktion abreißen.

function makeDeps(overrides: Partial<ShutdownDeps> = {}) {
  const calls: string[] = [];
  const deps: ShutdownDeps = {
    closeServer:     vi.fn(async () => { calls.push('closeServer'); }),
    flushMonitoring: vi.fn(async () => { calls.push('flushMonitoring'); }),
    closePools:      vi.fn(async () => { calls.push('closePools'); }),
    exit:            vi.fn((code: number) => { calls.push(`exit:${code}`); }),
    log:             { info: vi.fn(), error: vi.fn() },
    ...overrides,
  };
  return { deps, calls };
}

describe('createShutdown', () => {
  it('drained den Server, bevor die DB-Pools schließen (Reihenfolge ist die Zusage)', async () => {
    const { deps, calls } = makeDeps();

    await createShutdown(deps)('SIGTERM');

    expect(calls).toEqual(['closeServer', 'flushMonitoring', 'closePools', 'exit:0']);
  });

  it('meldet Fehler an das Monitoring, bevor der Prozess endet', async () => {
    // Sonst geht genau der Fehler verloren, der uns beendet hat.
    const { deps, calls } = makeDeps();

    await createShutdown(deps)('uncaughtException', 1);

    expect(calls.indexOf('flushMonitoring')).toBeLessThan(calls.indexOf('exit:1'));
    expect(deps.exit).toHaveBeenCalledWith(1);
  });

  it('reicht den Exit-Code durch (Fehlerpfad beendet mit 1)', async () => {
    const { deps } = makeDeps();
    await createShutdown(deps)('unhandledRejection', 1);
    expect(deps.exit).toHaveBeenCalledWith(1);
  });

  it('ist idempotent — ein zweites Signal startet den Drain nicht neu', async () => {
    // SIGTERM gefolgt von Ctrl-C darf die Pools nicht doppelt schließen.
    const { deps } = makeDeps();
    const shutdown = createShutdown(deps);

    await Promise.all([shutdown('SIGTERM'), shutdown('SIGINT')]);

    expect(deps.closePools).toHaveBeenCalledTimes(1);
    expect(deps.exit).toHaveBeenCalledTimes(1);
  });

  it('beendet mit 1, wenn ein Pool nicht sauber schließt', async () => {
    const { deps } = makeDeps({
      closePools: vi.fn(async () => { throw new Error('Pool hängt'); }),
    });

    await createShutdown(deps)('SIGTERM');

    expect(deps.exit).toHaveBeenCalledWith(1);
    expect(deps.log.error).toHaveBeenCalled();
  });

  it('behält den übergebenen Exit-Code auch im Fehlerfall', async () => {
    const { deps } = makeDeps({
      closePools: vi.fn(async () => { throw new Error('Pool hängt'); }),
    });

    await createShutdown(deps)('uncaughtException', 1);

    expect(deps.exit).toHaveBeenCalledWith(1);
  });

  describe('Notbremse bei hängendem Drain', () => {
    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    it('beendet hart, wenn der Server nicht innerhalb des Timeouts drained', async () => {
      // Realfall: ein iPad hält eine Keep-Alive-Verbindung, close() kehrt nie zurück.
      // Ohne Notbremse killt uns der Prozess-Manager später mit SIGKILL.
      const { deps } = makeDeps({
        closeServer: vi.fn(() => new Promise<void>(() => { /* kehrt nie zurück */ })),
        timeoutMs:   10_000,
      });

      void createShutdown(deps)('SIGTERM');
      await vi.advanceTimersByTimeAsync(10_000);

      expect(deps.exit).toHaveBeenCalledWith(1);
      expect(deps.closePools).not.toHaveBeenCalled();
    });

    it('beendet nicht doppelt, wenn der Drain nach dem Timeout doch noch fertig wird', async () => {
      let release: () => void = () => {};
      const { deps } = makeDeps({
        closeServer: vi.fn(() => new Promise<void>((res) => { release = res; })),
        timeoutMs:   10_000,
      });

      const done = createShutdown(deps)('SIGTERM');
      await vi.advanceTimersByTimeAsync(10_000);
      expect(deps.exit).toHaveBeenCalledTimes(1);

      release();
      await done;

      expect(deps.exit).toHaveBeenCalledTimes(1);
    });
  });
});

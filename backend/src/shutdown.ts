// shutdown.ts
// cashbox — Kontrolliertes Herunterfahren (OFFEN.md B6)
//
// Warum das bei einer Kasse mehr ist als Kosmetik: Ein `kill` mitten in payOrder
// bricht die DB-Transaktion ab, während die Bon-Nummer aus receipt_sequences
// schon gezogen sein kann. Wir müssen laufende Requests deshalb zu Ende laufen
// lassen (drain), bevor der Prozess geht — und danach die Pools schließen, damit
// MariaDB die Verbindungen nicht als abgerissen aufräumen muss.
//
// Reihenfolge ist bewusst: Server drainen → Monitoring flushen → Pools schließen.
// Erst wenn kein Request mehr läuft, darf die DB weg; und der Fehler, der uns
// beendet hat, muss bei Sentry sein, bevor der Prozess endet.
//
// Die Logik steckt hier als reine Funktion mit injizierten Abhängigkeiten (Muster
// wie validateSplitPartition), damit Reihenfolge, Idempotenz und der Timeout-Pfad
// ohne echten Server/DB testbar sind.

export interface ShutdownDeps {
  /** HTTP-Server drainen: keine neuen Verbindungen, laufende Requests zu Ende. */
  closeServer:     () => Promise<void>;
  /** Gepufferte Monitoring-Events rausschreiben (Sentry). */
  flushMonitoring: () => Promise<void>;
  /** Alle DB-Pools schließen. */
  closePools:      () => Promise<void>;
  exit:            (code: number) => void;
  log: {
    info:  (obj: object, msg: string) => void;
    error: (obj: object, msg: string) => void;
  };
  /**
   * Notbremse: Hängt der Drain (offene Keep-Alive-Verbindung, klemmender
   * DB-Lock), beenden wir trotzdem. Sonst schickt der Prozess-Manager
   * irgendwann SIGKILL — und das trifft uns garantiert unkontrolliert.
   */
  timeoutMs?: number;
}

export type ShutdownFn = (reason: string, exitCode?: number) => Promise<void>;

export function createShutdown(deps: ShutdownDeps): ShutdownFn {
  const timeoutMs = deps.timeoutMs ?? 10_000;
  let running = false;

  return async function shutdown(reason: string, exitCode = 0): Promise<void> {
    // Zweites Signal (z.B. SIGTERM dann SIGINT) darf den laufenden Drain nicht
    // neu starten — sonst schließen wir die Pools doppelt.
    if (running) {
      deps.log.info({ reason }, 'Shutdown läuft bereits — Signal ignoriert');
      return;
    }
    running = true;
    deps.log.info({ reason, timeoutMs }, 'Shutdown eingeleitet');

    let timedOut = false;
    const guard = setTimeout(() => {
      timedOut = true;
      deps.log.error({ reason, timeoutMs }, 'Shutdown-Timeout — harter Exit');
      deps.exit(exitCode === 0 ? 1 : exitCode);
    }, timeoutMs);
    // Der Timer selbst darf den Prozess nicht am Leben halten.
    if (typeof guard.unref === 'function') guard.unref();

    let code = exitCode;
    try {
      await deps.closeServer();
      deps.log.info({ reason }, 'HTTP-Server gedrained — keine offenen Requests mehr');

      await deps.flushMonitoring();

      await deps.closePools();
      deps.log.info({ reason }, 'DB-Pools geschlossen');
    } catch (err) {
      deps.log.error({ err, reason }, 'Fehler beim Shutdown');
      code = code === 0 ? 1 : code;
    } finally {
      clearTimeout(guard);
    }

    // Der Timeout-Pfad hat exit() schon gerufen; nicht doppelt beenden.
    if (timedOut) return;

    deps.log.info({ reason, exitCode: code }, 'Shutdown abgeschlossen');
    deps.exit(code);
  };
}

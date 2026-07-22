import { describe, it, expect } from 'vitest';
import {
  GRACE_PERIOD_DAYS,
  TRIAL_DAYS,
  graceEndsAt,
  trialExpiresAt,
  trialWarningMarker,
} from '../../services/subscription.js';

// REQ-CRON-001 (UC-CRON-01): Warnung und Sperre benutzen dieselben Fristen.
// Die Middleware sperrt nach TRIAL_DAYS — würde der Cron mit anderen Schwellen
// rechnen, bekäme der Wirt die "noch 1 Tag"-Mail, während die Kasse schon 402 gibt.

describe('trialExpiresAt / graceEndsAt', () => {
  it('setzt das Trial-Ende TRIAL_DAYS nach der Registrierung', () => {
    const created = new Date('2026-07-01T09:30:00Z');
    expect(trialExpiresAt(created).toISOString()).toBe('2026-07-15T09:30:00.000Z');
    expect(TRIAL_DAYS).toBe(14);
  });

  it('verschiebt das Ende der Kulanzfrist um GRACE_PERIOD_DAYS', () => {
    const periodEnd = new Date('2026-07-01T00:00:00Z');
    expect(graceEndsAt(periodEnd).toISOString()).toBe('2026-07-04T00:00:00.000Z');
    expect(GRACE_PERIOD_DAYS).toBe(3);
  });

  it('lässt die Eingabe unangetastet (kein Seiteneffekt auf das Original-Datum)', () => {
    const created = new Date('2026-07-01T09:30:00Z');
    trialExpiresAt(created);
    graceEndsAt(created);
    expect(created.toISOString()).toBe('2026-07-01T09:30:00.000Z');
  });
});

describe('trialWarningMarker', () => {
  it('warnt vor Tag 10 gar nicht', () => {
    for (const age of [0, 1, 5, 9]) {
      expect(trialWarningMarker(age)).toBeNull();
    }
  });

  it('warnt an Tag 10 einmal (4 Tage vor Ablauf)', () => {
    expect(trialWarningMarker(10)).toBe('day10');
  });

  it('bleibt bis Tag 12 bei day10 — ein ausgefallener Cron-Lauf holt die Warnung nach', () => {
    // Schwelle statt exaktem Tag: fällt der 6-Uhr-Lauf an Tag 10 aus, kommt die
    // Mail an Tag 11 — statt gar nicht. Dublette verhindert der Idempotenz-Key.
    expect(trialWarningMarker(11)).toBe('day10');
    expect(trialWarningMarker(12)).toBe('day10');
  });

  it('warnt an Tag 13 mit dem zweiten Marker', () => {
    expect(trialWarningMarker(13)).toBe('day13');
  });

  it('warnt ab Ablauf (Tag 14) nicht mehr — dann sperrt die Middleware', () => {
    expect(trialWarningMarker(14)).toBeNull();
    expect(trialWarningMarker(30)).toBeNull();
  });
});

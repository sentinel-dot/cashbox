// Formatierung für E-Mail-Inhalte. Bewusst pure Funktionen (CLAUDE.md: neue
// Geld-Logik = pure Funktion + Unit-Test), damit das Betragsformat testbar exakt
// dem Frontend entspricht — der Wirt sieht in der Mail dieselbe Zahl wie im iPad.

// Pendant zu `euroString()` in DesignSystem.swift: dort NumberFormatter(.decimal,
// de_DE, 2 Nachkommastellen) + " €". Gruppierung mit Punkt, Dezimalkomma,
// normales Leerzeichen vor dem €-Zeichen (kein NBSP — Swift hängt " €" an).
const euroFormatter = new Intl.NumberFormat('de-DE', {
  style: 'decimal',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** Cent → "1.234,56 €" (identisch zu euroString() im Frontend) */
export function euroString(cents: number): string {
  return `${euroFormatter.format(cents / 100)} €`;
}

const dateFormatter = new Intl.DateTimeFormat('de-DE', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  timeZone: 'Europe/Berlin',
});

const dateTimeFormatter = new Intl.DateTimeFormat('de-DE', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'Europe/Berlin',
});

/** Date → "20.07.2026" (Europe/Berlin — Mails zeigen immer Ortszeit des Betriebs) */
export function formatDate(d: Date): string {
  return dateFormatter.format(d);
}

/** Date → "20.07.2026, 14:30" */
export function formatDateTime(d: Date): string {
  return dateTimeFormatter.format(d);
}

/** Tage bis `until` (aufgerundet, nie negativ) — für Trial-Restzeit. */
export function daysUntil(until: Date, now: Date = new Date()): number {
  const ms = until.getTime() - now.getTime();
  return Math.max(0, Math.ceil(ms / 86_400_000));
}

/** "1 Tag" / "3 Tage" — Restzeit ohne Zahlwort-Stolperer im Fließtext. */
export function dayCountLabel(days: number): string {
  return days === 1 ? '1 Tag' : `${days} Tage`;
}

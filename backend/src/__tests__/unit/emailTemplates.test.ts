import { describe, it, expect } from 'vitest';
import { euroString, formatDate, formatDateTime, daysUntil, dayCountLabel } from '../../services/email/format.js';
import { esc, detailTable, renderEmail } from '../../services/email/layout.js';
import { renderTemplate, templates } from '../../services/email/templates.js';
import { backoffMinutes } from '../../services/email/queue.js';

// REQ-MAIL-001 — Betragsformat in Mails ist identisch zu euroString() im Frontend.
describe('euroString — deutsches Betragsformat (Parität zu DesignSystem.swift)', () => {
  it('formatiert mit Dezimalkomma und Tausenderpunkt', () => {
    expect(euroString(123456)).toBe('1.234,56 €');
  });

  it('erzwingt zwei Nachkommastellen', () => {
    expect(euroString(500)).toBe('5,00 €');
    expect(euroString(0)).toBe('0,00 €');
    expect(euroString(5)).toBe('0,05 €');
  });

  it('formatiert negative Beträge (Storno-Gegenbuchung)', () => {
    expect(euroString(-1990)).toBe('-19,90 €');
  });

  it('formatiert große Beträge (Tagesumsatz)', () => {
    expect(euroString(123456789)).toBe('1.234.567,89 €');
  });
});

// REQ-MAIL-002 — Datumsangaben in Mails stehen in Europe/Berlin, nicht UTC.
describe('formatDate / formatDateTime — Berliner Ortszeit', () => {
  it('formatiert als TT.MM.JJJJ', () => {
    expect(formatDate(new Date('2026-07-20T12:00:00Z'))).toBe('20.07.2026');
  });

  it('rechnet UTC in Berliner Zeit um (Sommerzeit +2h)', () => {
    // 22:30 UTC ist in Berlin bereits der Folgetag — dieselbe Falle wie bei den
    // Report-Tests (T9): ein UTC-Datum in der Mail wäre für den Wirt schlicht falsch.
    expect(formatDate(new Date('2026-07-20T22:30:00Z'))).toBe('21.07.2026');
    expect(formatDateTime(new Date('2026-07-20T22:30:00Z'))).toBe('21.07.2026, 00:30');
  });

  it('rechnet Winterzeit um (+1h)', () => {
    expect(formatDateTime(new Date('2026-01-15T08:00:00Z'))).toBe('15.01.2026, 09:00');
  });
});

describe('daysUntil / dayCountLabel — Trial-Restzeit', () => {
  const now = new Date('2026-07-20T10:00:00Z');

  it('rundet angebrochene Tage auf', () => {
    expect(daysUntil(new Date('2026-07-23T11:00:00Z'), now)).toBe(4);
    expect(daysUntil(new Date('2026-07-21T09:00:00Z'), now)).toBe(1);
  });

  it('liefert nie negative Tage (abgelaufener Trial)', () => {
    expect(daysUntil(new Date('2026-07-10T10:00:00Z'), now)).toBe(0);
  });

  it('setzt den Singular korrekt', () => {
    expect(dayCountLabel(1)).toBe('1 Tag');
    expect(dayCountLabel(3)).toBe('3 Tage');
  });
});

// REQ-MAIL-003 — Fremdtext in Mails wird escaped (kein HTML-Injection-Vektor).
describe('esc — HTML-Escaping', () => {
  it('escaped alle fünf kritischen Zeichen', () => {
    expect(esc(`<script>&"'`)).toBe('&lt;script&gt;&amp;&quot;&#39;');
  });

  it('escaped Betriebsnamen im Detail-Panel (Label-Spalte)', () => {
    const html = detailTable([{ label: '<b>Betrieb</b>', value: 'egal' }]);
    expect(html).not.toContain('<b>Betrieb</b>');
    expect(html).toContain('&lt;b&gt;Betrieb&lt;/b&gt;');
  });

  it('escaped die Überschrift im Rahmen', () => {
    const html = renderEmail({ preview: 'p', heading: '<img src=x>', bodyHtml: '' });
    expect(html).not.toContain('<img src=x>');
    expect(html).toContain('&lt;img src=x&gt;');
  });
});

// REQ-MAIL-004 — jedes Template liefert Betreff, HTML und Plaintext.
describe('Template-Registry', () => {
  it('jedes registrierte Template rendert alle drei Teile', () => {
    const samples = {
      trial_warning: {
        tenantName: 'Shishabar Test',
        trialEndsAt: new Date('2026-07-24T10:00:00Z'),
        upgradeUrl: 'https://app.cashbox.de/abo',
        now: new Date('2026-07-20T10:00:00Z'),
      },
    } as const;

    for (const name of Object.keys(templates) as (keyof typeof samples)[]) {
      const mail = renderTemplate(name, samples[name]);
      expect(mail.subject.length, `${name}: Betreff`).toBeGreaterThan(0);
      expect(mail.text.length, `${name}: Plaintext`).toBeGreaterThan(0);
      expect(mail.html, `${name}: HTML-Rahmen`).toContain('<!doctype html>');
      // 600px Single Column + Dark-Mode-Block sind Vorgabe aus OFFEN.md §5
      expect(mail.html, `${name}: Breite`).toContain('max-width:600px');
      expect(mail.html, `${name}: Dark Mode`).toContain('prefers-color-scheme: dark');
    }
  });
});

describe('Template: Trial-Warnung', () => {
  const base = {
    tenantName: 'Shishabar Test',
    trialEndsAt: new Date('2026-07-24T10:00:00Z'),
    upgradeUrl: 'https://app.cashbox.de/abo',
  };

  it('Tag 10 (4 Tage Rest): Restzeit in Betreff und Body', () => {
    const mail = renderTemplate('trial_warning', { ...base, now: new Date('2026-07-20T10:00:00Z') });
    expect(mail.subject).toBe('Dein cashbox-Test endet in 4 Tage');
    expect(mail.html).toContain('4 Tage');
    expect(mail.text).toContain('4 Tage');
  });

  it('Tag 13 (1 Tag Rest): eigener „morgen"-Wortlaut statt „1 Tag"', () => {
    const mail = renderTemplate('trial_warning', { ...base, now: new Date('2026-07-23T10:00:00Z') });
    expect(mail.subject).toBe('Dein cashbox-Test endet morgen');
    expect(mail.html).toContain('<strong>morgen</strong>');
    expect(mail.text).toContain('endet morgen');
  });

  it('nennt das Enddatum in Berliner Formatierung', () => {
    const mail = renderTemplate('trial_warning', { ...base, now: new Date('2026-07-20T10:00:00Z') });
    expect(mail.html).toContain('24.07.2026');
    expect(mail.text).toContain('24.07.2026');
  });

  it('enthält den Plan-CTA als Link (HTML und Plaintext)', () => {
    const mail = renderTemplate('trial_warning', { ...base, now: new Date('2026-07-20T10:00:00Z') });
    expect(mail.html).toContain('href="https://app.cashbox.de/abo"');
    expect(mail.text).toContain('https://app.cashbox.de/abo');
  });

  it('escaped den Betriebsnamen', () => {
    const mail = renderTemplate('trial_warning', {
      ...base,
      tenantName: 'Bar <script>alert(1)</script>',
      now: new Date('2026-07-20T10:00:00Z'),
    });
    expect(mail.html).not.toContain('<script>alert(1)</script>');
    expect(mail.html).toContain('&lt;script&gt;');
  });

  it('Du-Anrede statt Sie (Tonalität laut CLAUDE.md)', () => {
    const mail = renderTemplate('trial_warning', { ...base, now: new Date('2026-07-20T10:00:00Z') });
    expect(mail.text).toContain('dein Testzeitraum');
    expect(mail.text).not.toMatch(/\bIhr Testzeitraum\b/);
  });
});

// REQ-MAIL-005 — Fehlversand wird mit wachsendem Abstand erneut versucht.
describe('backoffMinutes — Retry-Abstände', () => {
  it('wächst monoton bis zum Deckel', () => {
    expect(backoffMinutes(1)).toBe(1);
    expect(backoffMinutes(2)).toBe(5);
    expect(backoffMinutes(3)).toBe(15);
    expect(backoffMinutes(4)).toBe(60);
    expect(backoffMinutes(5)).toBe(240);
  });

  it('deckelt über der Tabellenlänge (kein undefined im SQL-Parameter)', () => {
    expect(backoffMinutes(6)).toBe(240);
    expect(backoffMinutes(99)).toBe(240);
  });

  it('behandelt 0 wie den ersten Versuch', () => {
    expect(backoffMinutes(0)).toBe(1);
  });
});

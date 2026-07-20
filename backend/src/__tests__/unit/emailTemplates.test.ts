import { describe, it, expect } from 'vitest';
import {
  euroString, formatDate, formatDateTime, daysUntil, dayCountLabel,
  elapsedHours, hourCountLabel,
} from '../../services/email/format.js';
import { esc, detailTable, notice, renderEmail } from '../../services/email/layout.js';
import {
  renderTemplate, templates, type TemplateData, type TemplateName,
} from '../../services/email/templates.js';
import { emailIdempotencyKey } from '../../services/email/index.js';
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

describe('elapsedHours / hourCountLabel — Betriebswarnungen', () => {
  it('berechnet volle Stunden und wird nie negativ', () => {
    expect(elapsedHours(
      new Date('2026-07-18T08:00:00Z'),
      new Date('2026-07-20T09:45:00Z')
    )).toBe(49);
    expect(elapsedHours(
      new Date('2026-07-21T08:00:00Z'),
      new Date('2026-07-20T08:00:00Z')
    )).toBe(0);
  });

  it('setzt Singular und Plural korrekt', () => {
    expect(hourCountLabel(1)).toBe('1 Stunde');
    expect(hourCountLabel(49)).toBe('49 Stunden');
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

  it('nutzt für Hinweise eine vollständige Kontur statt einer Akzent-Seitenkante', () => {
    const html = notice('Wichtig', 'warn');
    expect(html).toContain('border:1px solid');
    expect(html).not.toContain('border-left');
  });
});

// REQ-MAIL-004 — jedes Template liefert Betreff, HTML und Plaintext.
describe('Template-Registry', () => {
  const samples: TemplateData = {
    trial_warning: {
      tenantName: 'Shishabar Test',
      trialEndsAt: new Date('2026-07-24T10:00:00Z'),
      upgradeUrl: 'https://app.cashbox.de/abo',
      now: new Date('2026-07-20T10:00:00Z'),
    },
    tse_outage: {
      tenantName: 'Shishabar Test',
      deviceName: 'iPad Theke',
      outageStartedAt: new Date('2026-07-18T08:00:00Z'),
      observedAt: new Date('2026-07-20T09:00:00Z'),
      elsterUrl: 'https://www.elster.de/eportal/start',
    },
    password_reset: {
      tenantName: 'Shishabar Test',
      resetUrl: 'https://app.cashbox.de/passwort/reset?token=test',
      expiresAt: new Date('2026-07-20T11:00:00Z'),
    },
    daily_z_report: {
      tenantName: 'Shishabar Test',
      reportDate: new Date('2026-07-20T12:00:00Z'),
      totalRevenueCents: 123456,
      payments: [
        { method: 'cash', amountCents: 100000 },
        { method: 'card', amountCents: 23456 },
      ],
      differenceCents: 0,
      reportUrl: 'https://app.cashbox.de/berichte/z/42',
    },
    subscription_event: {
      event: 'past_due',
      tenantName: 'Shishabar Test',
      billingUrl: 'https://app.cashbox.de/abo',
    },
    long_open_session: {
      tenantName: 'Shishabar Test',
      deviceName: 'iPad Theke',
      openedAt: new Date('2026-07-19T07:00:00Z'),
      observedAt: new Date('2026-07-20T09:00:00Z'),
      sessionUrl: 'https://app.cashbox.de/kassensitzung',
    },
  };

  function renderSample<K extends TemplateName>(name: K) {
    return renderTemplate(name, samples[name]);
  }

  it('enthält exakt die sechs in OFFEN.md definierten Template-Gruppen', () => {
    expect(Object.keys(templates)).toEqual([
      'trial_warning',
      'tse_outage',
      'password_reset',
      'daily_z_report',
      'subscription_event',
      'long_open_session',
    ]);
  });

  it('jedes registrierte Template rendert alle drei Teile', () => {
    for (const name of Object.keys(templates) as TemplateName[]) {
      const mail = renderSample(name);
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

describe('Template: TSE-Ausfall > 48h', () => {
  const base = {
    tenantName: 'Shishabar Test',
    deviceName: 'iPad Theke',
    outageStartedAt: new Date('2026-07-18T08:00:00Z'),
    observedAt: new Date('2026-07-20T09:30:00Z'),
    elsterUrl: 'https://www.elster.de/eportal/start',
  };

  it('enthält Zeitraum, Gerät, Dauer und ELSTER-Handlungsanweisung', () => {
    const mail = renderTemplate('tse_outage', base);
    expect(mail.subject).toContain('TSE-Ausfall');
    for (const value of ['iPad Theke', '18.07.2026, 10:00', '20.07.2026, 11:30', '49 Stunden']) {
      expect(mail.html).toContain(value);
      expect(mail.text).toContain(value);
    }
    expect(mail.html).toContain('Mein ELSTER öffnen');
    expect(mail.text).toContain(base.elsterUrl);
  });

  it('escaped Gerätename und Betriebsname', () => {
    const mail = renderTemplate('tse_outage', {
      ...base,
      tenantName: 'Bar <script>tenant</script>',
      deviceName: '<img src=x onerror=alert(1)>',
    });
    expect(mail.html).not.toContain('<script>tenant</script>');
    expect(mail.html).not.toContain('<img src=x onerror=alert(1)>');
    expect(mail.html).toContain('&lt;img src=x onerror=alert(1)&gt;');
  });
});

describe('Template: Passwort-Reset', () => {
  const data = {
    tenantName: 'Shishabar Test',
    resetUrl: 'https://app.cashbox.de/passwort/reset?token=abc&next=%2F',
    expiresAt: new Date('2026-07-20T11:00:00Z'),
  };

  it('enthält Token-Link und eindeutigen 1h-Hinweis in beiden Formaten', () => {
    const mail = renderTemplate('password_reset', data);
    expect(mail.subject).toBe('Dein cashbox-Passwort zurücksetzen');
    expect(mail.html).toContain('1 Stunde');
    expect(mail.html).toContain('20.07.2026, 13:00');
    expect(mail.html).toContain('token=abc&amp;next=%2F');
    expect(mail.text).toContain(data.resetUrl);
    expect(mail.text).toContain('1 Stunde');
  });

  it('erklärt den sicheren Ignorieren-Pfad', () => {
    const mail = renderTemplate('password_reset', data);
    expect(mail.text).toContain('nicht angefordert');
    expect(mail.text).toContain('Passwort bleibt unverändert');
  });
});

describe('Template: Z-Bericht-Tageszusammenfassung', () => {
  const base = {
    tenantName: 'Shishabar Test',
    reportDate: new Date('2026-07-20T12:00:00Z'),
    totalRevenueCents: 123456,
    payments: [
      { method: 'cash' as const, amountCents: 100000 },
      { method: 'card' as const, amountCents: 23456 },
    ],
    reportUrl: 'https://app.cashbox.de/berichte/z/42',
  };

  it('formatiert Umsatz, Zahlarten und ausgeglichene Kasse', () => {
    const mail = renderTemplate('daily_z_report', { ...base, differenceCents: 0 });
    for (const value of ['1.234,56 €', '1.000,00 €', '234,56 €', '0,00 €']) {
      expect(mail.html).toContain(value);
      expect(mail.text).toContain(value);
    }
    expect(mail.text).toContain('Kasse stimmt');
    expect(mail.html).toContain('href="https://app.cashbox.de/berichte/z/42"');
  });

  it('kennzeichnet Fehlbetrag und Überschuss mit absoluten Warnbeträgen', () => {
    const shortage = renderTemplate('daily_z_report', { ...base, differenceCents: -250 });
    expect(shortage.text).toContain('Kassendifferenz: -2,50 €');
    expect(shortage.text).toContain('Fehlbetrag: 2,50 €');

    const surplus = renderTemplate('daily_z_report', { ...base, differenceCents: 250 });
    expect(surplus.text).toContain('Kassendifferenz: 2,50 €');
    expect(surplus.text).toContain('Überschuss: 2,50 €');
  });
});

describe('Template: Subscription-Events', () => {
  it('past_due führt zur Zahlungsaktualisierung', () => {
    const mail = renderTemplate('subscription_event', {
      event: 'past_due', tenantName: 'Shishabar', billingUrl: 'https://app.cashbox.de/abo',
    });
    expect(mail.subject).toContain('fehlgeschlagen');
    expect(mail.text).toContain('Zahlung aktualisieren');
    expect(mail.html).toContain('href="https://app.cashbox.de/abo"');
  });

  it('Kündigung bestätigt Datum und Datenexport', () => {
    const mail = renderTemplate('subscription_event', {
      event: 'cancelled', tenantName: 'Shishabar',
      effectiveAt: new Date('2026-08-01T12:00:00Z'),
      dataExportUrl: 'https://app.cashbox.de/export',
    });
    expect(mail.subject).toContain('gekündigt');
    expect(mail.text).toContain('01.08.2026');
    expect(mail.text).toContain('Daten exportieren');
    expect(mail.text).toContain('Aufbewahrungsfrist');
  });

  it('Reaktivierung bestätigt die Freischaltung', () => {
    const mail = renderTemplate('subscription_event', {
      event: 'reactivated', tenantName: 'Shishabar', dashboardUrl: 'https://app.cashbox.de',
    });
    expect(mail.subject).toContain('wieder aktiv');
    expect(mail.text).toContain('Kassenbetrieb wie gewohnt fortsetzen');
  });
});

describe('Template: Session > 24h offen', () => {
  it('nennt Gerät, Beginn, Laufzeit und den Schließen-CTA', () => {
    const mail = renderTemplate('long_open_session', {
      tenantName: 'Shishabar',
      deviceName: 'iPad Theke',
      openedAt: new Date('2026-07-19T07:00:00Z'),
      observedAt: new Date('2026-07-20T09:45:00Z'),
      sessionUrl: 'https://app.cashbox.de/kassensitzung',
    });
    expect(mail.subject).toContain('über 24 Stunden');
    expect(mail.text).toContain('iPad Theke');
    expect(mail.text).toContain('19.07.2026, 09:00');
    expect(mail.text).toContain('26 Stunden');
    expect(mail.html).toContain('Kassensitzung prüfen');
  });
});

describe('emailIdempotencyKey — stabile Anlass-IDs ohne PII', () => {
  it('ist deterministisch und tenant-gescoped', () => {
    expect(emailIdempotencyKey('daily_z_report', 42, 9001))
      .toBe('daily_z_report:42:9001');
    expect(emailIdempotencyKey('daily_z_report', 43, 9001))
      .toBe('daily_z_report:43:9001');
  });

  it('nutzt für Reset nur die technische Anforderungs-ID', () => {
    const key = emailIdempotencyKey('password_reset', 42, 'request-uuid');
    expect(key).toBe('password_reset:42:request-uuid');
    expect(key).not.toContain('wirt@example.de');
    expect(key).not.toContain('secret-token');
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

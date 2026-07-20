// Die Template-Registry. Jedes Template liefert { subject, html, text } — Plaintext
// ist Pflicht (OFFEN.md §5): Mail-Clients ohne HTML und Spam-Filter bewerten eine
// reine HTML-Mail schlechter, und die KassenSichV-Meldemail muss ankommen.
import {
  euroString,
  formatDate,
  formatDateTime,
  daysUntil,
  dayCountLabel,
  elapsedHours,
  hourCountLabel,
} from './format.js';
import {
  renderEmail,
  detailTable,
  button,
  notice,
  paragraph,
  muted,
  money,
  esc,
} from './layout.js';

export type BuiltMail = { subject: string; html: string; text: string };

export type PaymentSummary = {
  method: 'cash' | 'card';
  amountCents: number;
};

export type SubscriptionEventData =
  | {
      event: 'past_due';
      tenantName: string;
      billingUrl: string;
    }
  | {
      event: 'cancelled';
      tenantName: string;
      effectiveAt: Date;
      dataExportUrl: string;
    }
  | {
      event: 'reactivated';
      tenantName: string;
      dashboardUrl: string;
    };

/** Payload je Template — der Compiler erzwingt am Aufrufort die richtigen Felder. */
export interface TemplateData {
  trial_warning: {
    tenantName: string;
    /** Ende des 14-Tage-Testzeitraums. */
    trialEndsAt: Date;
    upgradeUrl: string;
    /** Nur für Tests: fixer „Jetzt"-Zeitpunkt für die Restzeitberechnung. */
    now?: Date;
  };
  tse_outage: {
    tenantName: string;
    deviceName: string;
    outageStartedAt: Date;
    observedAt: Date;
    elsterUrl: string;
  };
  password_reset: {
    tenantName: string;
    resetUrl: string;
    expiresAt: Date;
  };
  daily_z_report: {
    tenantName: string;
    reportDate: Date;
    totalRevenueCents: number;
    payments: PaymentSummary[];
    differenceCents: number;
    reportUrl?: string;
  };
  subscription_event: SubscriptionEventData;
  long_open_session: {
    tenantName: string;
    deviceName: string;
    openedAt: Date;
    observedAt: Date;
    sessionUrl: string;
  };
}

export type TemplateName = keyof TemplateData;

function greeting(tenantName: string): string {
  return paragraph(`Hallo ${esc(tenantName)},`);
}

function paymentLabel(method: PaymentSummary['method']): string {
  return method === 'cash' ? 'Bar' : 'Karte';
}

// ── 1. Trial-Warnung (Tag 10 + 13) ──────────────────────────────────────────
function trialWarning(d: TemplateData['trial_warning']): BuiltMail {
  const days = daysUntil(d.trialEndsAt, d.now ?? new Date());
  const restLabel = dayCountLabel(days);
  const letzterTag = days <= 1;

  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${paragraph(
      letzterTag
        ? `dein Testzeitraum endet <strong>morgen</strong>. Danach lassen sich keine Bestellungen und Zahlungen mehr buchen, bis ein Abo aktiv ist.`
        : `dein Testzeitraum läuft noch <strong>${esc(restLabel)}</strong>. Danach lassen sich keine Bestellungen und Zahlungen mehr buchen, bis ein Abo aktiv ist.`
    )}
    ${detailTable([
      { label: 'Betrieb', value: esc(d.tenantName), strong: true },
      { label: 'Test endet am', value: esc(formatDate(d.trialEndsAt)) },
      { label: 'Verbleibend', value: esc(restLabel), strong: true },
    ])}
    ${button(d.upgradeUrl, 'Abo abschließen')}
    ${muted(
      'Deine Daten bleiben erhalten — Bons, Z-Berichte und Berichte sind auch nach Ablauf vollständig da. Es fehlt nur die Freigabe zum Weiterbuchen.'
    )}
  `;

  const text = [
    `Hallo ${d.tenantName},`,
    '',
    letzterTag
      ? 'dein Testzeitraum endet morgen. Danach lassen sich keine Bestellungen und'
      : `dein Testzeitraum läuft noch ${restLabel}. Danach lassen sich keine Bestellungen und`,
    'Zahlungen mehr buchen, bis ein Abo aktiv ist.',
    '',
    `Betrieb:        ${d.tenantName}`,
    `Test endet am:  ${formatDate(d.trialEndsAt)}`,
    `Verbleibend:    ${restLabel}`,
    '',
    `Abo abschließen: ${d.upgradeUrl}`,
    '',
    'Deine Daten bleiben erhalten — Bons, Z-Berichte und Berichte sind auch nach',
    'Ablauf vollständig da. Es fehlt nur die Freigabe zum Weiterbuchen.',
    '',
    'Fragen? support@cashbox.de',
  ].join('\n');

  return {
    subject: letzterTag
      ? 'Dein cashbox-Test endet morgen'
      : `Dein cashbox-Test endet in ${restLabel}`,
    html: renderEmail({
      preview: letzterTag
        ? 'Letzter Tag – danach ist kein Buchen mehr möglich.'
        : `Noch ${restLabel} – danach ist kein Buchen mehr möglich.`,
      heading: letzterTag ? 'Letzter Testtag' : `Noch ${restLabel} im Test`,
      bodyHtml,
    }),
    text,
  };
}

// ── 2. TSE-Ausfall > 48 Stunden ──────────────────────────────────────────────
function tseOutage(d: TemplateData['tse_outage']): BuiltMail {
  const hours = elapsedHours(d.outageStartedAt, d.observedAt);
  const duration = hourCountLabel(hours);
  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${notice(
      '<strong>Handlungsbedarf:</strong> Der TSE-Ausfall dauert länger als 48 Stunden und muss über Mein ELSTER an das Finanzamt gemeldet werden.',
      'danger'
    )}
    ${detailTable([
      { label: 'Gerät', value: esc(d.deviceName), strong: true },
      { label: 'Ausfall seit', value: esc(formatDateTime(d.outageStartedAt)) },
      { label: 'Stand', value: esc(formatDateTime(d.observedAt)) },
      { label: 'Bisherige Dauer', value: esc(duration), strong: true },
    ])}
    ${paragraph(
      'Melde den Ausfall jetzt über Mein ELSTER. Halte Beginn, betroffenes Gerät und die bisherige Dauer bereit. Die Kasse kann im dokumentierten Ausfallbetrieb weiterlaufen; offene Bons werden nach Wiederherstellung nachsigniert.'
    )}
    ${button(d.elsterUrl, 'Mein ELSTER öffnen')}
    ${muted(
      'Bewahre diese Nachricht als Nachweis auf. Prüfe nach Ende des Ausfalls zusätzlich, ob alle ausstehenden Bons eine TSE-Signatur erhalten haben.'
    )}
  `;

  return {
    subject: 'Handlungsbedarf: TSE-Ausfall länger als 48 Stunden',
    html: renderEmail({
      preview: `TSE-Ausfall auf ${d.deviceName}: Meldung über Mein ELSTER erforderlich.`,
      heading: 'TSE-Ausfall melden',
      bodyHtml,
      footerNote: 'Diese Meldung betrifft eine gesetzliche Aufzeichnungspflicht.',
    }),
    text: [
      `Hallo ${d.tenantName},`,
      '',
      'HANDLUNGSBEDARF: Der TSE-Ausfall dauert länger als 48 Stunden und muss',
      'über Mein ELSTER an das Finanzamt gemeldet werden.',
      '',
      `Gerät:          ${d.deviceName}`,
      `Ausfall seit:   ${formatDateTime(d.outageStartedAt)}`,
      `Stand:          ${formatDateTime(d.observedAt)}`,
      `Bisherige Dauer: ${duration}`,
      '',
      'Melde den Ausfall jetzt über Mein ELSTER. Halte Beginn, betroffenes Gerät',
      'und die bisherige Dauer bereit. Die Kasse kann im dokumentierten',
      'Ausfallbetrieb weiterlaufen; offene Bons werden nach Wiederherstellung nachsigniert.',
      '',
      `Mein ELSTER: ${d.elsterUrl}`,
      '',
      'Bewahre diese Nachricht als Nachweis auf. Prüfe nach Ende des Ausfalls,',
      'ob alle ausstehenden Bons eine TSE-Signatur erhalten haben.',
      '',
      'Fragen? support@cashbox.de',
    ].join('\n'),
  };
}

// ── 3. Passwort-Reset ────────────────────────────────────────────────────────
function passwordReset(d: TemplateData['password_reset']): BuiltMail {
  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${paragraph('du hast angefordert, dein cashbox-Passwort zurückzusetzen.')}
    ${button(d.resetUrl, 'Passwort zurücksetzen')}
    ${notice(
      `Der Link ist <strong>1 Stunde</strong> gültig, bis ${esc(formatDateTime(d.expiresAt))} Uhr. Danach musst du einen neuen Link anfordern.`,
      'info'
    )}
    ${muted(
      'Falls du diese Änderung nicht angefordert hast, kannst du die Nachricht ignorieren. Dein Passwort bleibt unverändert.'
    )}
  `;

  return {
    subject: 'Dein cashbox-Passwort zurücksetzen',
    html: renderEmail({
      preview: 'Dein persönlicher Reset-Link ist eine Stunde gültig.',
      heading: 'Passwort zurücksetzen',
      bodyHtml,
      footerNote: 'Der Link kann nur für diesen Passwort-Reset verwendet werden.',
    }),
    text: [
      `Hallo ${d.tenantName},`,
      '',
      'du hast angefordert, dein cashbox-Passwort zurückzusetzen.',
      '',
      `Passwort zurücksetzen: ${d.resetUrl}`,
      '',
      `Der Link ist 1 Stunde gültig, bis ${formatDateTime(d.expiresAt)} Uhr.`,
      'Danach musst du einen neuen Link anfordern.',
      '',
      'Falls du diese Änderung nicht angefordert hast, kannst du die Nachricht',
      'ignorieren. Dein Passwort bleibt unverändert.',
      '',
      'Fragen? support@cashbox.de',
    ].join('\n'),
  };
}

// ── 4. Z-Bericht-Tageszusammenfassung ────────────────────────────────────────
function dailyZReport(d: TemplateData['daily_z_report']): BuiltMail {
  const paymentRows = d.payments.map((payment) => ({
    label: paymentLabel(payment.method),
    value: money(euroString(payment.amountCents)),
  }));
  const differenceText = euroString(d.differenceCents);
  const balanced = d.differenceCents === 0;
  const differenceNotice = balanced
    ? notice('<strong>Kasse stimmt.</strong> Die gezählte Kasse entspricht dem erwarteten Bestand.', 'info')
    : notice(
        `<strong>${d.differenceCents < 0 ? 'Fehlbetrag' : 'Überschuss'}:</strong> ${money(euroString(Math.abs(d.differenceCents)))}. Bitte prüfe Zählung und Kassenbewegungen.`,
        'danger'
      );

  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${paragraph(`hier ist die Tageszusammenfassung für den ${esc(formatDate(d.reportDate))}.`)}
    ${detailTable([
      { label: 'Umsatz', value: money(euroString(d.totalRevenueCents)), strong: true, mono: true },
      ...paymentRows,
      { label: 'Kassendifferenz', value: money(differenceText), strong: true, mono: true },
    ])}
    ${differenceNotice}
    ${d.reportUrl ? button(d.reportUrl, 'Z-Bericht öffnen') : ''}
    ${muted('Der unveränderliche Z-Bericht bleibt zusätzlich in cashbox gespeichert.')}
  `;

  return {
    subject: `Z-Bericht vom ${formatDate(d.reportDate)}: ${euroString(d.totalRevenueCents)} Umsatz`,
    html: renderEmail({
      preview: `${euroString(d.totalRevenueCents)} Umsatz, Differenz ${differenceText}.`,
      heading: `Tagesabschluss · ${formatDate(d.reportDate)}`,
      bodyHtml,
    }),
    text: [
      `Hallo ${d.tenantName},`,
      '',
      `hier ist die Tageszusammenfassung für den ${formatDate(d.reportDate)}.`,
      '',
      `Umsatz:          ${euroString(d.totalRevenueCents)}`,
      ...d.payments.map(
        (payment) => `${paymentLabel(payment.method).padEnd(16)} ${euroString(payment.amountCents)}`
      ),
      `Kassendifferenz: ${differenceText}`,
      '',
      balanced
        ? 'Kasse stimmt. Die gezählte Kasse entspricht dem erwarteten Bestand.'
        : `${d.differenceCents < 0 ? 'Fehlbetrag' : 'Überschuss'}: ${euroString(Math.abs(d.differenceCents))}. Bitte prüfe Zählung und Kassenbewegungen.`,
      ...(d.reportUrl ? ['', `Z-Bericht öffnen: ${d.reportUrl}`] : []),
      '',
      'Der unveränderliche Z-Bericht bleibt zusätzlich in cashbox gespeichert.',
      '',
      'Fragen? support@cashbox.de',
    ].join('\n'),
  };
}

// ── 5. Subscription-Events (drei Zustände, eine Template-Gruppe) ─────────────
function subscriptionEvent(d: TemplateData['subscription_event']): BuiltMail {
  if (d.event === 'past_due') {
    const bodyHtml = `
      ${greeting(d.tenantName)}
      ${notice(
        '<strong>Zahlung fehlgeschlagen:</strong> Dein cashbox-Abo ist aktuell als überfällig markiert.',
        'warn'
      )}
      ${paragraph(
        'Prüfe jetzt deine Zahlungsmethode, damit der Kassenbetrieb nicht unterbrochen wird.'
      )}
      ${button(d.billingUrl, 'Zahlung aktualisieren')}
      ${muted('Bons, Z-Berichte und gesetzlich aufzubewahrende Daten bleiben erhalten.')}
    `;
    return {
      subject: 'Zahlung für dein cashbox-Abo fehlgeschlagen',
      html: renderEmail({
        preview: 'Bitte prüfe deine Zahlungsmethode.',
        heading: 'Zahlung prüfen',
        bodyHtml,
      }),
      text: [
        `Hallo ${d.tenantName},`,
        '',
        'die Zahlung für dein cashbox-Abo ist fehlgeschlagen. Dein Abo ist aktuell',
        'als überfällig markiert.',
        '',
        'Prüfe jetzt deine Zahlungsmethode, damit der Kassenbetrieb nicht unterbrochen wird.',
        `Zahlung aktualisieren: ${d.billingUrl}`,
        '',
        'Bons, Z-Berichte und gesetzlich aufzubewahrende Daten bleiben erhalten.',
        '',
        'Fragen? support@cashbox.de',
      ].join('\n'),
    };
  }

  if (d.event === 'cancelled') {
    const bodyHtml = `
      ${greeting(d.tenantName)}
      ${paragraph(
        `dein cashbox-Abo wurde zum <strong>${esc(formatDate(d.effectiveAt))}</strong> gekündigt.`
      )}
      ${notice(
        'Exportiere deine Daten rechtzeitig. Gesetzlich aufzubewahrende Kassendaten werden nicht vor Ablauf der Aufbewahrungsfrist gelöscht.',
        'info'
      )}
      ${button(d.dataExportUrl, 'Daten exportieren')}
      ${muted('Du kannst cashbox später mit einem neuen Abo wieder aktivieren.')}
    `;
    return {
      subject: 'Dein cashbox-Abo wurde gekündigt',
      html: renderEmail({
        preview: 'Kündigung bestätigt – bitte Datenexport prüfen.',
        heading: 'Kündigung bestätigt',
        bodyHtml,
      }),
      text: [
        `Hallo ${d.tenantName},`,
        '',
        `dein cashbox-Abo wurde zum ${formatDate(d.effectiveAt)} gekündigt.`,
        '',
        'Exportiere deine Daten rechtzeitig. Gesetzlich aufzubewahrende Kassendaten',
        'werden nicht vor Ablauf der Aufbewahrungsfrist gelöscht.',
        `Daten exportieren: ${d.dataExportUrl}`,
        '',
        'Du kannst cashbox später mit einem neuen Abo wieder aktivieren.',
        '',
        'Fragen? support@cashbox.de',
      ].join('\n'),
    };
  }

  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${notice('<strong>Alles bereit:</strong> Dein cashbox-Abo ist wieder aktiv.', 'info')}
    ${paragraph('Du kannst den Kassenbetrieb wie gewohnt fortsetzen. Deine bisherigen Daten sind weiterhin vorhanden.')}
    ${button(d.dashboardUrl, 'cashbox öffnen')}
  `;
  return {
    subject: 'Dein cashbox-Abo ist wieder aktiv',
    html: renderEmail({
      preview: 'Dein Abo ist aktiv und die Kasse wieder freigeschaltet.',
      heading: 'Abo reaktiviert',
      bodyHtml,
    }),
    text: [
      `Hallo ${d.tenantName},`,
      '',
      'dein cashbox-Abo ist wieder aktiv.',
      'Du kannst den Kassenbetrieb wie gewohnt fortsetzen. Deine bisherigen Daten',
      'sind weiterhin vorhanden.',
      '',
      `cashbox öffnen: ${d.dashboardUrl}`,
      '',
      'Fragen? support@cashbox.de',
    ].join('\n'),
  };
}

// ── 6. Kassensitzung länger als 24 Stunden offen ─────────────────────────────
function longOpenSession(d: TemplateData['long_open_session']): BuiltMail {
  const hours = elapsedHours(d.openedAt, d.observedAt);
  const duration = hourCountLabel(hours);
  const bodyHtml = `
    ${greeting(d.tenantName)}
    ${notice(
      '<strong>Kassensitzung noch offen:</strong> Prüfe, ob die Schicht bereits beendet werden sollte.',
      'warn'
    )}
    ${detailTable([
      { label: 'Gerät', value: esc(d.deviceName), strong: true },
      { label: 'Geöffnet seit', value: esc(formatDateTime(d.openedAt)) },
      { label: 'Bisherige Dauer', value: esc(duration), strong: true },
    ])}
    ${paragraph(
      'Eine offene Sitzung über mehrere Geschäftstage erschwert Kassensturz und Z-Bericht-Zuordnung. Prüfe offene Bestellungen und schließe die Schicht anschließend mit gezähltem Kassenbestand.'
    )}
    ${button(d.sessionUrl, 'Kassensitzung prüfen')}
  `;

  return {
    subject: 'Kassensitzung seit über 24 Stunden offen',
    html: renderEmail({
      preview: `${d.deviceName}: Kassensitzung seit ${duration} offen.`,
      heading: 'Offene Kassensitzung prüfen',
      bodyHtml,
    }),
    text: [
      `Hallo ${d.tenantName},`,
      '',
      'eine Kassensitzung ist seit mehr als 24 Stunden offen.',
      '',
      `Gerät:          ${d.deviceName}`,
      `Geöffnet seit:  ${formatDateTime(d.openedAt)}`,
      `Bisherige Dauer: ${duration}`,
      '',
      'Prüfe offene Bestellungen und schließe die Schicht anschließend mit',
      'gezähltem Kassenbestand.',
      '',
      `Kassensitzung prüfen: ${d.sessionUrl}`,
      '',
      'Fragen? support@cashbox.de',
    ].join('\n'),
  };
}

/** Registry: Name → Builder. Wird von `renderTemplate` und den Tests genutzt. */
export const templates: { [K in TemplateName]: (data: TemplateData[K]) => BuiltMail } = {
  trial_warning: trialWarning,
  tse_outage: tseOutage,
  password_reset: passwordReset,
  daily_z_report: dailyZReport,
  subscription_event: subscriptionEvent,
  long_open_session: longOpenSession,
};

export function renderTemplate<K extends TemplateName>(name: K, data: TemplateData[K]): BuiltMail {
  return templates[name](data);
}

export { euroString, formatDate, formatDateTime, elapsedHours, hourCountLabel };

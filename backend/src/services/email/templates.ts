// Die Template-Registry. Jedes Template liefert { subject, html, text } — Plaintext
// ist Pflicht (OFFEN.md §5): Mail-Clients ohne HTML und Spam-Filter bewerten eine
// reine HTML-Mail schlechter, und die KassenSichV-Meldemail muss ankommen.
//
// Neues Template (S06) = drei Handgriffe: Payload-Typ in `TemplateData` ergänzen,
// Builder schreiben, in `templates` eintragen. Der Rest (Queue, Log, Retry) ist
// template-agnostisch.
import { euroString, formatDate, formatDateTime, daysUntil, dayCountLabel } from './format.js';
import {
  renderEmail, detailTable, button, notice, paragraph, muted, sectionLabel, money, esc,
} from './layout.js';

export type BuiltMail = { subject: string; html: string; text: string };

/** Payload je Template — der Compiler erzwingt am Aufrufort die richtigen Felder. */
export interface TemplateData {
  trial_warning: {
    tenantName: string;
    /** Ende des 14-Tage-Testzeitraums (subscriptionMiddleware: created_at + 14 d) */
    trialEndsAt: Date;
    upgradeUrl: string;
    /** Nur für Tests: fixer „Jetzt"-Zeitpunkt für die Restzeitberechnung */
    now?: Date;
  };
}

export type TemplateName = keyof TemplateData;

// ── 1. Trial-Warnung (Tag 10 + 13) ──────────────────────────────────────────
// Ton: sachlich, kein Drohbrief. Der Wirt soll wissen, was am Stichtag passiert —
// und das ist konkret: subscriptionMiddleware gibt danach 402, es lässt sich keine
// Bestellung mehr buchen. Ehrlich benennen statt „Zugang eingeschränkt".
function trialWarning(d: TemplateData['trial_warning']): BuiltMail {
  const days = daysUntil(d.trialEndsAt, d.now ?? new Date());
  const restLabel = dayCountLabel(days);
  const letzterTag = days <= 1;

  const bodyHtml = `
    ${paragraph(`Hallo ${esc(d.tenantName)},`)}
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

/** Registry: Name → Builder. Wird von `renderTemplate` und den Tests genutzt. */
export const templates: { [K in TemplateName]: (data: TemplateData[K]) => BuiltMail } = {
  trial_warning: trialWarning,
};

export function renderTemplate<K extends TemplateName>(name: K, data: TemplateData[K]): BuiltMail {
  return templates[name](data);
}

// Re-Export für Templates in S06, die diese Bausteine direkt brauchen.
export { euroString, formatDate, formatDateTime, notice, sectionLabel, money };

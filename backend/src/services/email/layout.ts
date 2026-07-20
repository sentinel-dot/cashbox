// Gemeinsame E-Mail-Bausteine (OFFEN.md §5). Tabellen-Layout + Inline-Styles, weil
// Mail-Clients weder externe Stylesheets noch modernes CSS zuverlässig können.
// Dark-Mode zusätzlich über Klassen im <style>-Block: Inline-Styles gewinnen sonst
// gegen die Media-Query, deshalb dort durchgängig `!important`.
import { mail, fontBody, fontMono } from './palette.js';

const L = mail.light;
const D = mail.dark;

/** Pflicht für jeden eingebetteten Fremdtext (Betriebsname, Gerätename, Fehlertext)
 *  — sonst HTML-Injection in der Mail. */
export function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function paragraph(html: string): string {
  return `<p class="ds-text" style="margin:0 0 16px;font-family:${fontBody};font-size:16px;line-height:1.6;color:${L.text};">${html}</p>`;
}

export function muted(html: string): string {
  return `<p class="ds-muted" style="margin:0 0 16px;font-family:${fontBody};font-size:14px;line-height:1.55;color:${L.text2};">${html}</p>`;
}

/** Ruhiges Label über einem Panel (Pendant zu DSSectionLabel). */
export function sectionLabel(text: string): string {
  return `<div class="ds-muted" style="margin:0 0 8px;font-family:${fontBody};font-size:13px;font-weight:600;color:${L.text2};">${esc(text)}</div>`;
}

export type DetailRow = { label: string; value: string; strong?: boolean; mono?: boolean };

/** Daten-Panel (Betrag, Zeitraum, Gerät …): Label links gedämpft, Wert rechts.
 *  `value` wird NICHT escaped — Aufrufer escapen selbst bzw. übergeben Markup. */
export function detailTable(rows: DetailRow[]): string {
  const trs = rows
    .map(
      (r, i) => `
      <tr>
        <td class="ds-muted" style="padding:${i === 0 ? '0' : '10px'} 0 0 0;font-family:${fontBody};font-size:14px;color:${L.text2};vertical-align:top;white-space:nowrap;">${esc(r.label)}</td>
        <td class="ds-text" style="padding:${i === 0 ? '0' : '10px'} 0 0 16px;font-family:${r.mono ? fontMono : fontBody};font-size:${r.strong ? '17px' : '15px'};font-weight:${r.strong ? '600' : '400'};color:${L.text};text-align:right;vertical-align:top;">${r.value}</td>
      </tr>`
    )
    .join('');
  return `
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         class="ds-panel" style="margin:22px 0;background:${L.sur2};border:1px solid ${L.brd};border-radius:14px;">
    <tr><td style="padding:20px 22px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${trs}</table>
    </td></tr>
  </table>`;
}

/** Bulletproof-Button in Akzentgrün. bgcolor auf der Zelle ist der Outlook-Fallback. */
export function button(href: string, label: string): string {
  return `
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 4px;">
    <tr><td align="center" bgcolor="${L.acc}" class="ds-btn" style="border-radius:10px;background:${L.acc};">
      <a href="${esc(href)}" target="_blank"
         style="display:inline-block;padding:14px 28px;font-family:${fontBody};font-size:16px;font-weight:600;color:${L.onAcc};text-decoration:none;border-radius:10px;">${esc(label)}</a>
    </td></tr>
  </table>`;
}

/** Vollflächige Hinweisbox für Fristen, Pflichtmeldungen und Warnungen. */
export function notice(html: string, tone: 'info' | 'warn' | 'danger' = 'info'): string {
  const map = {
    info: { bg: L.accBg, fg: L.accT, cls: 'ds-notice-info' },
    warn: { bg: L.brassBg, fg: L.brassText, cls: 'ds-notice-warn' },
    danger: { bg: L.dangerBg, fg: L.dangerText, cls: 'ds-notice-danger' },
  }[tone];
  return `
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:20px 0;">
    <tr><td class="${map.cls}" style="padding:16px 18px;background:${map.bg};border:1px solid ${map.fg};border-radius:10px;font-family:${fontBody};font-size:15px;line-height:1.55;color:${map.fg};">${html}</td></tr>
  </table>`;
}

/** Betrag in Tabellenziffern — für Fließtext ("Umsatz: 1.234,56 €"). */
export function money(text: string): string {
  return `<span style="font-family:${fontMono};font-variant-numeric:tabular-nums;">${esc(text)}</span>`;
}

const SUPPORT_MAIL = 'support@cashbox.de';

/** Der äußere Rahmen: Markenkopf (Blattgrün-Marke auf Panel-Grün), weiße Inhaltskarte,
 *  Footer mit Absenderklarheit. `preview` = versteckte Inbox-Vorschauzeile. */
export function renderEmail(opts: {
  preview: string;
  heading: string;
  bodyHtml: string;
  footerNote?: string;
}): string {
  const year = new Date().getFullYear();
  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${esc(opts.heading)}</title>
<style>
  @media (prefers-color-scheme: dark) {
    .ds-body    { background:${D.bg} !important; }
    .ds-card    { background:${D.sur} !important; border-color:${D.brd} !important; }
    .ds-panel   { background:${D.sur2} !important; border-color:${D.brd} !important; }
    .ds-footer  { background:${D.sur2} !important; border-color:${D.brd} !important; }
    .ds-text, .ds-heading { color:${D.text} !important; }
    .ds-muted   { color:${D.text2} !important; }
    .ds-link    { color:${D.accT} !important; }
    .ds-btn     { background:${D.acc} !important; }
    .ds-notice-info   { background:${D.accBg} !important;    color:${D.accT} !important;      border-color:${D.accT} !important; }
    .ds-notice-warn   { background:${D.brassBg} !important;  color:${D.brassText} !important; border-color:${D.brassText} !important; }
    .ds-notice-danger { background:${D.dangerBg} !important; color:${D.dangerText} !important; border-color:${D.dangerText} !important; }
  }
  @media only screen and (max-width:620px) {
    .ds-pad { padding-left:22px !important; padding-right:22px !important; }
  }
</style>
<!--[if mso]><style>body,table,td,a{font-family:'Segoe UI',Arial,sans-serif !important;}</style><![endif]-->
</head>
<body class="ds-body" style="margin:0;padding:0;background:${L.bg};-webkit-text-size-adjust:100%;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${esc(opts.preview)}</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="ds-body" style="background:${L.bg};">
    <tr><td align="center" style="padding:32px 16px;">

      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" class="ds-card"
             style="width:600px;max-width:600px;background:${L.sur};border:1px solid ${L.brd};border-radius:16px;overflow:hidden;">

        <!-- Kopf: dieselbe Wortmarke wie der Login-Screen (Blattgrün-Kachel + €) -->
        <tr><td bgcolor="${L.brandPanel}" class="ds-pad" style="padding:22px 36px;background:${L.brandPanel};">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0">
            <tr>
              <td width="34" style="width:34px;">
                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="34" height="34"
                       style="width:34px;height:34px;background:${L.brandLeaf};border-radius:9px;">
                  <tr><td align="center" valign="middle" style="font-family:${fontBody};font-size:17px;font-weight:700;color:${L.brandPanel};line-height:34px;">&euro;</td></tr>
                </table>
              </td>
              <td style="padding-left:12px;font-family:${fontBody};font-size:19px;font-weight:700;color:#FFFFFF;letter-spacing:-0.01em;">cashbox</td>
            </tr>
          </table>
        </td></tr>

        <!-- Inhalt -->
        <tr><td class="ds-pad" style="padding:32px 36px 34px;">
          <h1 class="ds-heading" style="margin:0 0 18px;font-family:${fontBody};font-size:24px;line-height:1.25;font-weight:700;color:${L.text};letter-spacing:-0.01em;">${esc(opts.heading)}</h1>
          ${opts.bodyHtml}
        </td></tr>

        <!-- Footer -->
        <tr><td class="ds-footer ds-pad" style="padding:22px 36px 26px;background:${L.sur2};border-top:1px solid ${L.brd};">
          <div class="ds-muted" style="font-family:${fontBody};font-size:13px;line-height:1.6;color:${L.text2};">
            ${opts.footerNote ? `${opts.footerNote}<br>` : ''}
            Fragen? Schreib uns an <a href="mailto:${SUPPORT_MAIL}" class="ds-link" style="color:${L.accT};">${SUPPORT_MAIL}</a>.
          </div>
          <div class="ds-muted" style="font-family:${fontBody};font-size:12px;color:${L.text2};margin-top:10px;">&copy; ${year} cashbox &middot; Kassensystem f&uuml;r die Gastronomie</div>
        </td></tr>

      </table>

    </td></tr>
  </table>
</body>
</html>`;
}

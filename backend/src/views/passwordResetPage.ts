// views/passwordResetPage.ts — S08: die einzige HTML-Seite, die dieses Backend
// ausliefert. Sie existiert, weil der Reset-Link aus der Mail irgendwo landen
// muss und es (noch) kein Web-Frontend gibt: Der Wirt öffnet ihn auf dem Handy,
// setzt das Passwort und meldet sich danach am iPad neu an.
//
// Bewusst ohne JavaScript: Kein Framework, kein CDN, keine CSP-Ausnahme
// (helmets Default erlaubt Inline-*Styles*, aber keine Inline-*Skripte*).
// Passwortvergleich und Validierung laufen deshalb serverseitig.
//
// Alle Render-Funktionen sind pure — Eingabe rein, HTML-String raus. Damit sind
// Escaping und Fehlertexte unit-testbar (CLAUDE.md: neue Logik = pure Funktion
// + Unit-Test).
import { mail, fontBody } from '../services/email/palette.js';
import type { ConsumeFailure } from '../services/passwordReset.js';

const L = mail.light;
const D = mail.dark;

/** Eigenes esc statt des Pendants aus `services/email/layout.ts`: Das ist der
 *  Mail-Kontext (Inline-Styles, Tabellen-Layout), das hier eine echte HTML5-
 *  Seite. Ein gemeinsamer Import würde die beiden Ebenen ohne Not verkoppeln. */
export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Mindestlänge — identisch zum Zod-Schema im Controller, damit die Seite nicht
 *  strenger oder laxer aussieht als der Server prüft. */
export const MIN_PASSWORD_LENGTH = 8;

const styles = `
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px 16px 48px;
    font-family: ${fontBody};
    background: ${L.bg}; color: ${L.text};
    -webkit-text-size-adjust: 100%;
  }
  .wrap { max-width: 420px; margin: 0 auto; }
  .brand {
    font-size: 15px; font-weight: 600; letter-spacing: .02em;
    color: ${L.text2}; text-align: center; margin: 8px 0 20px;
  }
  .brand span { color: ${L.accT}; }
  .card {
    background: ${L.sur}; border: 1px solid ${L.brd}; border-radius: 14px;
    padding: 24px 20px;
  }
  h1 { margin: 0 0 8px; font-size: 21px; line-height: 1.3; }
  p { margin: 0 0 16px; font-size: 15px; line-height: 1.55; color: ${L.text2}; }
  label { display: block; font-size: 13px; font-weight: 600; margin: 0 0 6px; color: ${L.text}; }
  input[type=password] {
    width: 100%; padding: 12px 14px; font-size: 16px; font-family: inherit;
    color: ${L.text}; background: ${L.bg};
    border: 1px solid ${L.brd}; border-radius: 10px; margin: 0 0 16px;
  }
  input[type=password]:focus { outline: 2px solid ${L.acc}; outline-offset: 1px; }
  button {
    width: 100%; padding: 14px 16px; font-size: 16px; font-weight: 600;
    font-family: inherit; color: ${L.onAcc}; background: ${L.acc};
    border: 0; border-radius: 10px; cursor: pointer;
  }
  .note { font-size: 13px; color: ${L.text2}; margin: 16px 0 0; }
  .banner {
    border-radius: 10px; padding: 12px 14px; margin: 0 0 16px;
    font-size: 14px; line-height: 1.5;
  }
  .banner.err { background: ${L.dangerBg}; color: ${L.dangerText}; }
  .banner.ok  { background: ${L.accBg};    color: ${L.accT}; }
  @media (prefers-color-scheme: dark) {
    body { background: ${D.bg}; color: ${D.text}; }
    .brand { color: ${D.text2}; }
    .brand span { color: ${D.accT}; }
    .card { background: ${D.sur}; border-color: ${D.brd}; }
    p, .note { color: ${D.text2}; }
    label { color: ${D.text}; }
    input[type=password] { background: ${D.bg}; color: ${D.text}; border-color: ${D.brd}; }
    button { background: ${D.acc}; color: ${D.onAcc}; }
    .banner.err { background: ${D.dangerBg}; color: ${D.dangerText}; }
    .banner.ok  { background: ${D.accBg};    color: ${D.accT}; }
  }
`;

function page(title: string, bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHtml(title)} · cashbox</title>
<style>${styles}</style>
</head>
<body>
<div class="wrap">
  <div class="brand">cash<span>box</span></div>
  <div class="card">
${bodyHtml}
  </div>
</div>
</body>
</html>`;
}

/** Formular zum Setzen des neuen Passworts. `error` erscheint als Banner —
 *  z.B. wenn die beiden Eingaben nicht übereinstimmen. */
export function renderResetFormPage(input: { token: string; error?: string }): string {
  const banner = input.error
    ? `    <div class="banner err">${escapeHtml(input.error)}</div>\n`
    : '';

  return page(
    'Passwort zurücksetzen',
    `${banner}    <h1>Neues Passwort setzen</h1>
    <p>Wähle ein neues Passwort für dein cashbox-Konto. Danach meldest du dich am iPad damit an.</p>
    <form method="post" action="/auth/reset-password" autocomplete="off">
      <input type="hidden" name="token" value="${escapeHtml(input.token)}">
      <label for="new_password">Neues Passwort</label>
      <input type="password" id="new_password" name="new_password"
             autocomplete="new-password" minlength="${MIN_PASSWORD_LENGTH}" required>
      <label for="new_password_repeat">Passwort wiederholen</label>
      <input type="password" id="new_password_repeat" name="new_password_repeat"
             autocomplete="new-password" minlength="${MIN_PASSWORD_LENGTH}" required>
      <button type="submit">Passwort speichern</button>
    </form>
    <p class="note">Mindestens ${MIN_PASSWORD_LENGTH} Zeichen. Der Link gilt eine Stunde und nur ein einziges Mal.</p>`
  );
}

export function renderResetSuccessPage(): string {
  return page(
    'Passwort geändert',
    `    <div class="banner ok">Passwort geändert.</div>
    <h1>Erledigt</h1>
    <p>Du kannst dich jetzt am iPad mit deinem neuen Passwort anmelden. Offene Sitzungen auf allen Geräten wurden beendet.</p>
    <p class="note">Diese Seite kannst du schließen.</p>`
  );
}

/** Warum der Link nicht funktioniert — in Klartext, nicht als Fehlercode.
 *  Kein Enumerationsrisiko: Wer hier steht, hält den Token bereits in der Hand. */
export function failureMessage(reason: ConsumeFailure): string {
  switch (reason) {
    case 'expired':
      return 'Dieser Link ist abgelaufen. Fordere in der App unter „Passwort vergessen" einen neuen an.';
    case 'used':
      return 'Dieser Link wurde bereits verwendet. Fordere in der App unter „Passwort vergessen" einen neuen an.';
    case 'user_inactive':
      return 'Dieses Konto ist nicht mehr aktiv. Wende dich an den Betriebsinhaber.';
    case 'invalid':
    default:
      return 'Dieser Link ist ungültig. Prüfe, ob du ihn vollständig kopiert hast, oder fordere einen neuen an.';
  }
}

export function renderResetErrorPage(reason: ConsumeFailure): string {
  return page(
    'Link ungültig',
    `    <div class="banner err">${escapeHtml(failureMessage(reason))}</div>
    <h1>Link nicht mehr gültig</h1>
    <p>Aus Sicherheitsgründen sind Reset-Links nur eine Stunde und nur einmal verwendbar.</p>
    <p class="note">Neuen Link anfordern: In der cashbox-App auf dem Anmeldebildschirm auf „Passwort vergessen" tippen.</p>`
  );
}

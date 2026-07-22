// S08 (OFFEN.md B3) — pure Anteile des Passwort-Resets: Token-Erzeugung,
// Hashing, Link-Bau, Redaktion fürs Logging und das Rendering der Reset-Seite.
// Alles ohne DB — die Datenbankpfade deckt integration/password-reset.test.ts ab.
import { describe, it, expect, afterEach } from 'vitest';
import { redactUrl } from '../../logger.js';
import {
  generateResetToken,
  hashResetToken,
  passwordResetUrl,
  RESET_TTL_MINUTES,
  MAX_REQUESTS_PER_HOUR,
} from '../../services/passwordReset.js';
import {
  escapeHtml,
  failureMessage,
  renderResetErrorPage,
  renderResetFormPage,
  renderResetSuccessPage,
  MIN_PASSWORD_LENGTH,
} from '../../views/passwordResetPage.js';

describe('generateResetToken', () => {
  it('liefert bei jedem Aufruf einen anderen Token', () => {
    const tokens = new Set(Array.from({ length: 200 }, () => generateResetToken()));
    expect(tokens.size).toBe(200);
  });

  it('ist URL-sicher (base64url — kein +, / oder =)', () => {
    for (let i = 0; i < 50; i++) {
      expect(generateResetToken()).toMatch(/^[A-Za-z0-9_-]+$/);
    }
  });

  it('trägt 32 Byte Entropie (43 base64url-Zeichen)', () => {
    expect(generateResetToken()).toHaveLength(43);
  });
});

describe('hashResetToken', () => {
  it('ist deterministisch', () => {
    expect(hashResetToken('abc')).toBe(hashResetToken('abc'));
  });

  it('liefert 64 Hex-Zeichen (SHA-256) — passt in CHAR(64)', () => {
    expect(hashResetToken(generateResetToken())).toMatch(/^[0-9a-f]{64}$/);
  });

  it('unterscheidet sich für unterschiedliche Token', () => {
    expect(hashResetToken('abc')).not.toBe(hashResetToken('abd'));
  });

  it('gibt den Klartext-Token nicht preis', () => {
    const raw = generateResetToken();
    expect(hashResetToken(raw)).not.toContain(raw);
  });
});

describe('passwordResetUrl', () => {
  const original = process.env['PUBLIC_API_URL'];
  afterEach(() => {
    if (original === undefined) delete process.env['PUBLIC_API_URL'];
    else process.env['PUBLIC_API_URL'] = original;
  });

  it('zeigt auf PUBLIC_API_URL (das Backend rendert die Seite, nicht die App)', () => {
    process.env['PUBLIC_API_URL'] = 'https://api.example.de';
    expect(passwordResetUrl('tok123')).toBe(
      'https://api.example.de/auth/reset-password?token=tok123'
    );
  });

  it('verträgt einen abschließenden Slash in der Basis-URL', () => {
    process.env['PUBLIC_API_URL'] = 'https://api.example.de/';
    expect(passwordResetUrl('tok123')).toBe(
      'https://api.example.de/auth/reset-password?token=tok123'
    );
  });

  it('kodiert den Token für die Query', () => {
    process.env['PUBLIC_API_URL'] = 'https://api.example.de';
    expect(passwordResetUrl('a b&c')).toContain('token=a%20b%26c');
  });
});

describe('Konstanten', () => {
  it('Gültigkeit ist die eine Stunde, die das Mail-Template zusagt', () => {
    expect(RESET_TTL_MINUTES).toBe(60);
  });

  it('Stundenlimit pro Nutzer bremst Mail-Bombing', () => {
    expect(MAX_REQUESTS_PER_HOUR).toBeGreaterThan(0);
    expect(MAX_REQUESTS_PER_HOUR).toBeLessThanOrEqual(5);
  });
});

describe('redactUrl (Token darf nicht ins Logfile)', () => {
  it('entfernt die Query der Reset-Route vollständig', () => {
    expect(redactUrl('/auth/reset-password?token=geheim123')).toBe('/auth/reset-password?REDACTED');
  });

  it('lässt den Token auch bei weiteren Query-Parametern nicht durch', () => {
    const redacted = redactUrl('/auth/reset-password?foo=1&token=geheim123&bar=2');
    expect(redacted).not.toContain('geheim123');
  });

  it('lässt andere URLs unverändert', () => {
    expect(redactUrl('/orders?status=open')).toBe('/orders?status=open');
    expect(redactUrl('/auth/login')).toBe('/auth/login');
    expect(redactUrl('/auth/reset-password')).toBe('/auth/reset-password');
  });
});

describe('escapeHtml', () => {
  it('entschärft alle fünf HTML-kritischen Zeichen', () => {
    expect(escapeHtml(`<&">'`)).toBe('&lt;&amp;&quot;&gt;&#39;');
  });
});

describe('renderResetFormPage', () => {
  it('enthält Formular, Token und beide Passwortfelder', () => {
    const html = renderResetFormPage({ token: 'tok123' });
    expect(html).toContain('<form method="post" action="/auth/reset-password"');
    expect(html).toContain('name="token" value="tok123"');
    expect(html).toContain('name="new_password"');
    expect(html).toContain('name="new_password_repeat"');
  });

  it('nennt die Mindestlänge, die der Server auch prüft', () => {
    expect(renderResetFormPage({ token: 't' })).toContain(`Mindestens ${MIN_PASSWORD_LENGTH} Zeichen`);
  });

  it('escaped einen manipulierten Token — kein Ausbruch aus dem value-Attribut', () => {
    const html = renderResetFormPage({ token: '"><script>alert(1)</script>' });
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&quot;&gt;&lt;script&gt;');
  });

  it('zeigt eine Fehlermeldung als Banner an', () => {
    const html = renderResetFormPage({ token: 't', error: 'Passwörter stimmen nicht überein.' });
    expect(html).toContain('banner err');
    expect(html).toContain('Passwörter stimmen nicht überein.');
  });

  it('kommt ohne JavaScript aus (helmet-CSP erlaubt keine Inline-Skripte)', () => {
    const html = renderResetFormPage({ token: 't' });
    expect(html).not.toContain('<script');
    expect(html).not.toContain('onclick');
  });
});

describe('failureMessage', () => {
  it('unterscheidet abgelaufen, verbraucht, inaktiv und ungültig', () => {
    const msgs = (['expired', 'used', 'user_inactive', 'invalid'] as const).map(failureMessage);
    expect(new Set(msgs).size).toBe(4);
    msgs.forEach((m) => expect(m.length).toBeGreaterThan(20));
  });

  it('nennt für abgelaufene Links den Weg zum neuen Link', () => {
    expect(failureMessage('expired')).toContain('Passwort vergessen');
  });
});

describe('Ergebnisseiten', () => {
  it('Erfolgsseite verweist auf die Anmeldung am iPad', () => {
    const html = renderResetSuccessPage();
    expect(html).toContain('iPad');
    expect(html).not.toContain('<form');
  });

  it('Fehlerseite bietet kein Formular an (nichts mehr abzusenden)', () => {
    expect(renderResetErrorPage('expired')).not.toContain('<form');
  });

  it('sind vollständige, deutschsprachige HTML-Dokumente', () => {
    for (const html of [renderResetSuccessPage(), renderResetErrorPage('used'), renderResetFormPage({ token: 't' })]) {
      expect(html.startsWith('<!DOCTYPE html>')).toBe(true);
      expect(html).toContain('<html lang="de">');
      expect(html).toContain('name="viewport"');
      // Suchmaschinen haben auf einer Token-Seite nichts verloren
      expect(html).toContain('noindex');
    }
  });
});

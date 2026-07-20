// Low-Level-Versand über die Resend-REST-API. Bewusst ohne npm-SDK — ein fetch
// genügt, und jede Abhängigkeit weniger ist eine Supply-Chain-Fläche weniger.
// Ohne RESEND_API_KEY läuft ein Dry-Run: Dev und CI versenden nie nach außen.
import { logger } from '../../logger.js';

export type SendInput = {
  to: string;
  subject: string;
  html: string;
  text: string;
  replyTo?: string | undefined;
};

/** Resend antwortet mit der Message-ID — sie landet als Nachweis in email_log. */
export type SendResult = { providerMessageId: string | null };

const RESEND_ENDPOINT = 'https://api.resend.com/emails';

// Fiskaly nutzt 10 s; hier 15 s, weil ein Mail-Versand nie in einem Request-Pfad
// hängt (die Queue drained asynchron) und Resend-Latenz gutmütiger sein darf.
const TIMEOUT_MS = 15_000;

/** Absender MUSS auf der verifizierten Domain liegen (SPF/DKIM/DMARC), sonst Spam. */
function mailFrom(): string {
  return process.env['MAIL_FROM'] ?? 'cashbox <noreply@cashbox.de>';
}

export function isDryRun(): boolean {
  return !process.env['RESEND_API_KEY'];
}

/** Sendet genau eine Mail. Wirft bei Fehler — die Queue fängt und retryt. */
export async function sendMail(input: SendInput): Promise<SendResult> {
  if (isDryRun()) {
    logger.info(
      { to: input.to, subject: input.subject },
      '[mail:dry-run] nicht versendet (kein RESEND_API_KEY)'
    );
    return { providerMessageId: null };
  }

  const res = await fetch(RESEND_ENDPOINT, {
    method: 'POST',
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: {
      Authorization: `Bearer ${process.env['RESEND_API_KEY']}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: mailFrom(),
      to: [input.to],
      subject: input.subject,
      html: input.html,
      text: input.text,
      ...(input.replyTo ? { reply_to: input.replyTo } : {}),
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Resend ${res.status}: ${detail.slice(0, 300)}`);
  }

  const body = (await res.json().catch(() => ({}))) as { id?: string };
  return { providerMessageId: body.id ?? null };
}

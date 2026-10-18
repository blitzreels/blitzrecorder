/** Sends one email through Resend. Throws when Resend does not accept it. */
export async function sendEmail({
  apiKey,
  from,
  to,
  subject,
  text,
  html,
  idempotencyKey,
}: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  text: string;
  html: string;
  idempotencyKey: string;
}): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({ from, to: [to], subject, text, html }),
  });
  if (!response.ok) throw new Error("delivery");
}

import { createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { transaction } from "./db";
import { connectAccountInTransaction } from "./account";
import { assertHostingEnabled, HostingError, required, tokenHash } from "./model";

const invalidCode = () => new HostingError({ status: 400, message: "This code is invalid or expired. Request a new code and try again." });

function digest(value: string) {
  return createHmac("sha256", required("HOSTING_AUTH_SECRET")).update(value).digest("hex");
}

export function signInEmail(body: unknown): string {
  const email = body && typeof body === "object" && "email" in body ? body.email : null;
  if (typeof email !== "string" || email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    throw new HostingError({ status: 400, message: "Enter your email address." });
  }
  return email.trim().toLowerCase();
}

export async function requestSignInCode({ body, network }: { body: unknown; network: string }) {
  assertHostingEnabled();
  const email = signInEmail(body);
  const apiKey = required("HOSTING_EMAIL_API_KEY");
  const from = required("HOSTING_EMAIL_FROM");
  if (!/^BlitzRecorder <[^<>\s]+@(?:[a-z0-9-]+\.)?blitzrecorder\.com>$/.test(from)) {
    throw new HostingError({ status: 503, message: "BlitzRecorder email sign-in is not configured yet." });
  }
  const challenge = randomBytes(32).toString("base64url");
  const hash = tokenHash(challenge);
  const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
  const networkHash = digest(`network:${network}`);
  await transaction(async (db) => {
    await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`sign-in-network:${networkHash}`]);
    await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`sign-in-email:${email}`]);
    const limits = (await db.query<{ recent: string; hourly: string; network: string }>(
      `SELECT count(*) FILTER (WHERE email=$1 AND created_at>now()-interval '1 minute') AS recent,
       count(*) FILTER (WHERE email=$1) AS hourly,
       count(*) FILTER (WHERE network_hash=$2) AS network
       FROM hosting_sign_in_codes WHERE created_at>now()-interval '1 hour' AND (email=$1 OR network_hash=$2)`,
      [email, networkHash])).rows[0];
    if (Number(limits.recent) > 0 || Number(limits.hourly) >= 5 || Number(limits.network) >= 20) {
      throw new HostingError({ status: 429, message: "Please wait before requesting another sign-in code." });
    }
    await db.query("DELETE FROM hosting_sign_in_codes WHERE created_at<now()-interval '1 day'");
    await db.query("INSERT INTO hosting_sign_in_codes(challenge_hash,email,code_hash,network_hash) VALUES($1,$2,$3,$4)",
      [hash, email, digest(`${challenge}:${code}`), networkHash]);
  });
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", "Idempotency-Key": `hosting-sign-in/${hash}` },
      body: JSON.stringify({ from, to: [email], subject: `${code} is your BlitzRecorder sign-in code`,
        text: `Your BlitzRecorder sign-in code is ${code}.\n\nEnter it in BlitzRecorder to create or access your account. It expires in 10 minutes.\n\nIf you did not request this code, you can ignore this email.`,
        html: `<div style="font-family:system-ui,sans-serif;max-width:480px;margin:auto;padding:32px;color:#171717"><p style="font-weight:700">BlitzRecorder</p><h1 style="font-size:24px">Your sign-in code</h1><p>Enter this code in BlitzRecorder to create or access your account.</p><p style="font-size:36px;font-weight:700;letter-spacing:8px">${code}</p><p>This code expires in 10 minutes.</p><p style="color:#737373;font-size:13px">If you did not request this code, you can ignore this email.</p></div>` }),
    });
    if (!response.ok) throw new Error("delivery");
  } catch {
    throw new HostingError({ status: 503, message: "We could not confirm email delivery. If no code arrives, wait a minute and try again." });
  }
  return { challenge, email, expiresIn: 600, retryAfter: 60 };
}

export async function verifySignInCode(body: unknown) {
  assertHostingEnabled();
  const input = body as { challenge?: unknown; code?: unknown } | null;
  if (typeof input?.challenge !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(input.challenge)
    || typeof input.code !== "string" || !/^\d{6}$/.test(input.code)) throw invalidCode();
  const challenge = input.challenge;
  const code = input.code;
  const result = await transaction(async (db) => {
    const row = (await db.query<{ email: string; code_hash: string; attempts: number; verified_at: Date | null; expires_at: Date }>(
      "SELECT * FROM hosting_sign_in_codes WHERE challenge_hash=$1 FOR UPDATE", [tokenHash(challenge)])).rows[0];
    if (!row || row.verified_at || row.expires_at.getTime() <= Date.now() || row.attempts >= 5) return null;
    await db.query("UPDATE hosting_sign_in_codes SET attempts=attempts+1 WHERE challenge_hash=$1", [tokenHash(challenge)]);
    const expected = Buffer.from(row.code_hash, "hex");
    const given = Buffer.from(digest(`${challenge}:${code}`), "hex");
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;
    const account = await connectAccountInTransaction({ id: `email:${row.email}`, email: row.email, db });
    await db.query("UPDATE hosting_sign_in_codes SET verified_at=now() WHERE challenge_hash=$1", [tokenHash(challenge)]);
    return account;
  });
  if (!result) throw invalidCode();
  return result;
}

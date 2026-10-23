import { createHash } from "node:crypto";
import { sendEmail } from "@/lib/email";
import { SITE_URL } from "@/lib/site";

/** True when the email form asked for the Mac download link, not a waitlist. */
export function isDownloadLinkSource(source: string): boolean {
  return source.startsWith("download_link");
}

/**
 * Emails the Mac download link to someone who visited on a phone or PC.
 * Returns false when email is not configured, so the caller can say so.
 */
export async function sendDownloadLinkEmail({ email }: { email: string }): Promise<boolean> {
  const apiKey = process.env.HOSTING_EMAIL_API_KEY;
  const from = process.env.HOSTING_EMAIL_FROM;
  if (!apiKey || !from) return false;
  await sendEmail({
    apiKey,
    from,
    to: email,
    idempotencyKey: `download-link/${createHash("sha256").update(email).digest("hex")}`,
    subject: "Your BlitzRecorder download link",
    text: `Here is BlitzRecorder for your Mac. Open this link on the Mac you want to record on:\n\n${SITE_URL}\n\nIt's free, with no account and no watermark. It needs macOS 15 or later.`,
    html: `<div style="font-family:system-ui,sans-serif;max-width:480px;margin:auto;padding:32px;color:#171717"><p style="font-weight:700">BlitzRecorder</p><h1 style="font-size:24px">Open this on your Mac</h1><p>BlitzRecorder is free, with no account and no watermark. It needs macOS 15 or later.</p><p><a href="${SITE_URL}" style="display:inline-block;background:#17ffa6;color:#000;font-weight:700;padding:12px 20px;border-radius:8px;text-decoration:none">Download for Mac</a></p><p style="color:#737373;font-size:13px">You asked for this link on blitzrecorder.com. We won't email you again.</p></div>`,
  });
  return true;
}

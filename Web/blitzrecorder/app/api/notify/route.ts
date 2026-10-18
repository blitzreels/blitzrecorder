import { clientNetwork } from "@/lib/client-network";
import { type NextRequest, NextResponse } from "next/server";
import { isDownloadLinkSource, sendDownloadLinkEmail } from "@/lib/download-link-email";
import { claimDownloadEmail, recordNotifySignup, releaseDownloadEmail } from "@/lib/notify-store";

export const runtime = "nodejs";

// Conservative RFC-5322-ish check; we only need to reject obvious junk.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function str(value: unknown, max: number): string | null {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
}

export async function POST(request: NextRequest) {
  let body: Record<string, unknown> | null = null;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid request." }, { status: 400 });
  }

  const email = str(body?.email, 320)?.toLowerCase() ?? null;
  if (!email || !EMAIL_RE.test(email)) {
    return NextResponse.json({ ok: false, error: "Enter a valid email." }, { status: 400 });
  }

  const requested = str(body?.source, 80);
  const source = requested && /^[a-z0-9_]+$/.test(requested) ? requested : "site_notify";
  const os = str(body?.os, 40);

  const attribution: Record<string, string> = {};
  const visitorId = request.cookies.get("datafast_visitor_id")?.value;
  if (visitorId) attribution.datafast_visitor_id = visitorId.slice(0, 500);
  const referer = request.headers.get("referer");
  if (referer) attribution.referrer = referer.slice(0, 500);

  try {
    const signup = await recordNotifySignup({ email, source, os, attribution });
    // One download email per address, ever, so the form can't be used to fill someone's inbox.
    const claim = isDownloadLinkSource(source)
      ? await claimDownloadEmail({ email, network: clientNetwork(request) })
      : null;
    if (claim === "limited") {
      return NextResponse.json({ ok: false, error: "Too many requests from this network. Try again in an hour." }, { status: 429 });
    }
    if (claim === "claimed") {
      const sent = await sendDownloadLinkEmail({ email }).catch(() => false);
      if (!sent) {
        await releaseDownloadEmail(email);
        return NextResponse.json({ ok: false, error: "We couldn’t send the email. Try again in a minute." }, { status: 503 });
      }
    }
    // Report success even when the store is unconfigured (dev/preview): the
    // visitor experience is unchanged and production has POSTGRES_URL set.
    return NextResponse.json({ ok: true, stored: signup !== "unconfigured" });
  } catch {
    return NextResponse.json({ ok: false, error: "Something went wrong. Please try again." }, { status: 500 });
  }
}

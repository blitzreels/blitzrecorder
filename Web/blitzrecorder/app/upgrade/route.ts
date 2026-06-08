import { type NextRequest, NextResponse } from "next/server";
import { createEarlyPriceCheckoutSession } from "@/lib/payments";

export const runtime = "nodejs";

/**
 * One-click upgrade entry point. Used by the Mac app's in-app paywall
 * (`blitzrecorder://` -> "Unlock") and by any "buy now" link, so a high-intent
 * buyer lands straight in Stripe checkout instead of back on the marketing
 * homepage. Carries source + locked-feature attribution so DataFast and the
 * Stripe metadata can segment in-app upgrade intent.
 *
 * GET so it works as a plain link target (NSWorkspace.open, anchors, emails).
 * On any failure it degrades to the pricing section rather than erroring.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const source = (url.searchParams.get("source") || "upgrade_link").slice(0, 80);
  const feature = url.searchParams.get("feature")?.slice(0, 80) || null;

  const attribution: Record<string, string> = { checkout_source: source };
  if (feature) attribution.upgrade_feature = feature;

  const visitorId = request.cookies.get("datafast_visitor_id")?.value;
  const sessionId = request.cookies.get("datafast_session_id")?.value;
  if (visitorId) attribution.datafast_visitor_id = visitorId.slice(0, 500);
  if (sessionId) attribution.datafast_session_id = sessionId.slice(0, 500);

  try {
    const session = await createEarlyPriceCheckoutSession({
      requestUrl: request.url,
      attributionMetadata: attribution,
    });
    if (session.url) {
      return NextResponse.redirect(session.url, 303);
    }
  } catch {
    // Fall through to the pricing section below.
  }

  return NextResponse.redirect(new URL("/#pricing", url), 303);
}

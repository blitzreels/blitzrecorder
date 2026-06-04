import { type NextRequest, NextResponse } from "next/server";
import { createEarlyPriceCheckoutSession } from "@/lib/payments";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData().catch(() => null);
    const emailValue = formData?.get("email");
    const email = typeof emailValue === "string" ? emailValue : null;
    const datafastVisitorId = request.cookies.get("datafast_visitor_id")?.value;
    const datafastSessionId = request.cookies.get("datafast_session_id")?.value;
    const attributionMetadata: Record<string, string> = {};
    if (datafastVisitorId) attributionMetadata.datafast_visitor_id = datafastVisitorId;
    if (datafastSessionId) attributionMetadata.datafast_session_id = datafastSessionId;

    const session = await createEarlyPriceCheckoutSession({
      requestUrl: request.url,
      email,
      attributionMetadata,
    });

    if (!session.url) {
      return NextResponse.json({ error: "Stripe did not return a checkout URL" }, { status: 502 });
    }

    return NextResponse.redirect(session.url, 303);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to create checkout session" },
      { status: 500 },
    );
  }
}

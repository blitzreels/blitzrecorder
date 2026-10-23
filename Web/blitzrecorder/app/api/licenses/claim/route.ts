import { NextResponse } from "next/server";
import { CheckoutSessionNotEligible, claimLicenseForCheckoutSession } from "@/lib/licenses";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const sessionId = new URL(request.url).searchParams.get("session_id");
  if (!sessionId) {
    return NextResponse.json({ error: "Missing session_id" }, { status: 400 });
  }

  try {
    const license = await claimLicenseForCheckoutSession({
      sessionId,
      stripeAccountId: null,
      storeWrite: "best_effort",
    });
    return NextResponse.json(license);
  } catch (error) {
    if (error instanceof CheckoutSessionNotEligible) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("License claim failed", error instanceof Error ? error.message : error);
    return NextResponse.json({ error: "Unable to claim license right now. Try again later." }, { status: 500 });
  }
}

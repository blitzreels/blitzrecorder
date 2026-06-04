import { NextResponse } from "next/server";
import { claimLicenseForCheckoutSession } from "@/lib/licenses";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const sessionId = new URL(request.url).searchParams.get("session_id");
  if (!sessionId) {
    return NextResponse.json({ error: "Missing session_id" }, { status: 400 });
  }

  try {
    const license = await claimLicenseForCheckoutSession(sessionId);
    return NextResponse.json(license);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to claim license" },
      { status: 400 },
    );
  }
}

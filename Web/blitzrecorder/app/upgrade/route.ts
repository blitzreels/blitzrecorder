import { type NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

/**
 * In-app unlock entry. The Mac paywall opens this as a plain GET.
 * Licenses are free now, so this lands on the email claim form with source
 * attribution still attached for DataFast.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const source = (url.searchParams.get("source") || "upgrade_link").slice(0, 80);
  const feature = url.searchParams.get("feature")?.slice(0, 80) || null;

  const dest = new URL("/license", url);
  dest.searchParams.set("source", source);
  if (feature) dest.searchParams.set("feature", feature);
  return NextResponse.redirect(dest, 303);
}

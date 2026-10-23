import { NextResponse } from "next/server";
import { clientNetwork } from "@/lib/client-network";
import { licenseKeyHash, validateLicenseKey } from "@/lib/licenses";
import { createRateLimiter } from "@/lib/rate-limit";

export const runtime = "nodejs";

const perNetwork = createRateLimiter({ limit: 60, windowMs: 10 * 60 * 1000 });
const perLicenseKey = createRateLimiter({ limit: 20, windowMs: 10 * 60 * 1000 });

function rateLimited() {
  return NextResponse.json(
    { ok: false, status: "rate_limited", reason: "Too many requests. Try again in a few minutes." },
    { status: 429, headers: { "Retry-After": "600" } },
  );
}

export async function POST(request: Request) {
  if (!perNetwork.allow(clientNetwork(request))) {
    return rateLimited();
  }

  const body = (await request.json().catch(() => null)) as { licenseKey?: unknown } | null;
  if (typeof body?.licenseKey !== "string") {
    return NextResponse.json({ ok: false, status: "invalid", reason: "Missing licenseKey" }, { status: 400 });
  }
  if (!perLicenseKey.allow(licenseKeyHash(body.licenseKey))) {
    return rateLimited();
  }

  try {
    const validation = await validateLicenseKey(body.licenseKey);
    return NextResponse.json(validation, { status: validation.ok ? 200 : 400 });
  } catch (error) {
    console.error("License validation failed", error instanceof Error ? error.message : error);
    return NextResponse.json(
      { ok: false, status: "invalid", reason: "Unable to validate license right now. Try again later." },
      { status: 500 },
    );
  }
}

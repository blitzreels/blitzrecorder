import { NextResponse } from "next/server";
import { validateLicenseKey } from "@/lib/licenses";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { licenseKey?: unknown };
    if (typeof body.licenseKey !== "string") {
      return NextResponse.json({ ok: false, status: "invalid", reason: "Missing licenseKey" }, { status: 400 });
    }

    const validation = await validateLicenseKey(body.licenseKey);
    return NextResponse.json(validation, { status: validation.ok ? 200 : 400 });
  } catch (error) {
    return NextResponse.json(
      { ok: false, status: "invalid", reason: error instanceof Error ? error.message : "Unable to validate license" },
      { status: 500 },
    );
  }
}

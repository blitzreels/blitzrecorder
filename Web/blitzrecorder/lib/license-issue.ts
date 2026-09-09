import { type NextRequest, NextResponse } from "next/server";
import {
  createFreeLicenseGrant,
  isValidLicenseEmail,
  issueFreeLicense,
  normalizeLicenseEmail,
} from "@/lib/licenses";
import { getSiteUrl } from "@/lib/payments";

const ATTRIBUTION_FIELDS = [
  "landing_path",
  "landing_referrer",
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "gclid",
  "fbclid",
  "msclkid",
  "ttclid",
] as const;

function formString(formData: FormData | null, key: string): string | null {
  const value = formData?.get(key);
  return typeof value === "string" ? value : null;
}

function metadataValue(value: string | null | undefined, maxLength = 500): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed.slice(0, maxLength) : null;
}

export async function handleFreeLicenseIssue(request: NextRequest): Promise<NextResponse> {
  try {
    const formData = await request.formData().catch(() => null);
    const email = metadataValue(formString(formData, "email"), 320);
    if (!email || !isValidLicenseEmail(email)) {
      return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
    }
    const checkoutSource = metadataValue(formString(formData, "source"), 80) ?? "unknown";
    const datafastVisitorId = request.cookies.get("datafast_visitor_id")?.value;
    const datafastSessionId = request.cookies.get("datafast_session_id")?.value;
    const attributionMetadata: Record<string, string> = {};
    attributionMetadata.checkout_source = checkoutSource;
    attributionMetadata.license_kind = "free";
    if (datafastVisitorId) attributionMetadata.datafast_visitor_id = datafastVisitorId.slice(0, 500);
    if (datafastSessionId) attributionMetadata.datafast_session_id = datafastSessionId.slice(0, 500);

    for (const field of ATTRIBUTION_FIELDS) {
      const fallbackValue =
        field === "landing_referrer" ? request.headers.get("referer") : undefined;
      const value = metadataValue(formString(formData, field) ?? fallbackValue);
      if (value) {
        attributionMetadata[field] = value;
      }
    }

    await issueFreeLicense(normalizeLicenseEmail(email), attributionMetadata);
    const siteUrl = getSiteUrl(request.url);
    const grant = createFreeLicenseGrant(email);
    const claimUrl = new URL("/license/claim", siteUrl);
    claimUrl.searchParams.set("grant", grant);
    return NextResponse.redirect(claimUrl, 303);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to issue license" },
      { status: 500 },
    );
  }
}

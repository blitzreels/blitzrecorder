import crypto from "node:crypto";
import type Stripe from "stripe";
import { earlyPrice, getBlitzRecorderEarlyPriceId, getStripe } from "@/lib/payments";
import {
  getPaymentIntentRevocation,
  getLicense,
  isLicenseStoreConfigured,
  upsertLicenseWithContext,
} from "@/lib/license-store";

export type LicensePayload = {
  version: 1;
  app: "blitzrecorder";
  licenseId: string;
  kind: "early_lifetime";
  plan: "early_lifetime_2026";
  maxDevices: null;
  grandfathered: true;
  email: string;
  stripeSessionId: string;
  stripeCustomerId: string | null;
  stripePaymentIntentId: string | null;
  stripePriceId: string;
  issuedAt: number;
};

export type ClaimedLicense = {
  licenseId: string;
  email: string;
  licenseKey: string;
  payload: LicensePayload;
};

export type LicenseClaimContext = {
  stripeAccountId?: string | null;
};

export type LicenseValidation =
  | { ok: true; status: "active"; payload: LicensePayload }
  | {
      ok: false;
      status: "invalid" | "unpaid" | "refunded" | "revoked" | "wrong_product";
      reason: string;
    };

function licenseSecret(): string {
  const secret = process.env.BLITZRECORDER_LICENSE_SECRET;
  if (secret) {
    return secret;
  }

  if (process.env.NODE_ENV !== "production") {
    return "dev-only-blitzrecorder-license-secret";
  }

  throw new Error("Missing BLITZRECORDER_LICENSE_SECRET");
}

function base64url(input: string | Buffer): string {
  return Buffer.from(input).toString("base64url");
}

function unbase64url(input: string): string {
  return Buffer.from(input, "base64url").toString("utf8");
}

function hmac(value: string): string {
  return crypto.createHmac("sha256", licenseSecret()).update(value).digest("base64url");
}

function stableLicenseId(sessionId: string): string {
  return `br_${crypto.createHmac("sha256", licenseSecret()).update(`license:${sessionId}`).digest("hex").slice(0, 20)}`;
}

function signPayload(payload: LicensePayload): string {
  const body = base64url(JSON.stringify(payload));
  const signature = hmac(body);
  return `BRL1.${body}.${signature}`;
}

function isManualSignedLicense(payload: LicensePayload): boolean {
  return (
    payload.kind === "early_lifetime" &&
    payload.plan === "early_lifetime_2026" &&
    payload.grandfathered === true &&
    payload.stripeSessionId.startsWith("manual_") &&
    payload.stripeCustomerId === null &&
    payload.stripePaymentIntentId === null
  );
}

export function decodeLicenseKey(licenseKey: string): LicensePayload {
  const { body, signature } = licenseKeyParts(licenseKey);
  const expected = hmac(body);
  const given = Buffer.from(signature);
  const wanted = Buffer.from(expected);
  if (given.length !== wanted.length || !crypto.timingSafeEqual(given, wanted)) {
    throw new Error("License signature is invalid");
  }

  const payload = JSON.parse(unbase64url(body)) as LicensePayload;
  if (payload.version !== 1 || payload.app !== "blitzrecorder") {
    throw new Error("License payload is invalid");
  }

  return payload;
}

function licenseKeyParts(licenseKey: string): { body: string; signature: string } {
  const key = licenseKey.trim();

  if (key.startsWith("BRL1.")) {
    const parts = key.split(".");
    if (parts.length !== 3 || !parts[1] || !parts[2]) {
      throw new Error("License key format is invalid");
    }
    return { body: parts[1], signature: parts[2] };
  }

  if (!key.startsWith("BRL1_")) {
    throw new Error("License key format is invalid");
  }

  // Legacy keys used "_" as a separator, but base64url output may also contain
  // underscores. Try each possible separator and keep the one that verifies.
  const rest = key.slice("BRL1_".length);
  for (let index = rest.indexOf("_"); index !== -1; index = rest.indexOf("_", index + 1)) {
    const body = rest.slice(0, index);
    const signature = rest.slice(index + 1);
    if (!body || !signature) {
      continue;
    }
    if (hmac(body) === signature) {
      return { body, signature };
    }
  }

  throw new Error("License signature is invalid");
}

function stripeId(value: string | { id: string } | null | undefined): string | null {
  if (!value) {
    return null;
  }
  return typeof value === "string" ? value : value.id;
}

function sessionPriceIds(session: Stripe.Checkout.Session): string[] {
  return (
    session.line_items?.data
      .map((item) => {
        const price = item.price;
        return typeof price === "string" ? price : price?.id;
      })
      .filter((id): id is string => Boolean(id)) ?? []
  );
}

function assertPaidBlitzRecorderSession(session: Stripe.Checkout.Session): void {
  const priceId = getBlitzRecorderEarlyPriceId();
  if (session.mode !== "payment") {
    throw new Error("Checkout session is not a one-time payment");
  }
  if (session.payment_status !== "paid") {
    throw new Error("Checkout session is not paid");
  }
  if (!sessionPriceIds(session).includes(priceId)) {
    throw new Error("Checkout session is not for the BlitzRecorder lifetime license");
  }
}

function sessionAttribution(session: Stripe.Checkout.Session): Record<string, string> {
  return Object.fromEntries(
    Object.entries(session.metadata ?? {}).filter((entry): entry is [string, string] =>
      typeof entry[1] === "string",
    ),
  );
}

function storeContextForSession(
  session: Stripe.Checkout.Session,
  context: LicenseClaimContext = {},
) {
  const attribution = sessionAttribution(session);
  return {
    stripeLivemode: session.livemode,
    stripeAccountId:
      context.stripeAccountId ??
      attribution.stripe_account_id ??
      process.env.STRIPE_ACCOUNT_ID ??
      null,
    attribution,
  };
}

export async function claimLicenseForCheckoutSession(
  sessionId: string,
  context: LicenseClaimContext = {},
): Promise<ClaimedLicense> {
  const stripe = getStripe();
  const priceId = getBlitzRecorderEarlyPriceId();
  const session = await stripe.checkout.sessions.retrieve(sessionId, {
    expand: ["line_items.data.price", "payment_intent", "customer"],
  });

  assertPaidBlitzRecorderSession(session);

  const customerEmail =
    typeof session.customer !== "string" && session.customer && !("deleted" in session.customer)
      ? session.customer.email
      : null;
  const email = session.customer_details?.email ?? customerEmail;

  if (!email) {
    throw new Error("Checkout session does not include a customer email");
  }

  const payload: LicensePayload = {
    version: 1,
    app: "blitzrecorder",
    licenseId: stableLicenseId(session.id),
    kind: "early_lifetime",
    plan: "early_lifetime_2026",
    maxDevices: null,
    grandfathered: true,
    email,
    stripeSessionId: session.id,
    stripeCustomerId: stripeId(session.customer),
    stripePaymentIntentId: stripeId(session.payment_intent),
    stripePriceId: priceId,
    issuedAt: session.created,
  };

  // Record the license when a store is configured. Claiming must not fail on
  // a database hiccup: the key is still valid without the row.
  if (isLicenseStoreConfigured()) {
    await upsertLicenseWithContext(payload, storeContextForSession(session, context)).catch(() => {});
  }

  return {
    licenseId: payload.licenseId,
    email,
    licenseKey: signPayload(payload),
    payload,
  };
}

type StripePaymentRevocation = "refunded" | "disputed" | null;

async function paymentRevocationStatus(paymentIntentId: string | null): Promise<StripePaymentRevocation> {
  if (!paymentIntentId) {
    return null;
  }

  const paymentIntent = await getStripe().paymentIntents.retrieve(paymentIntentId, {
    expand: ["latest_charge"],
  });

  const charge = paymentIntent.latest_charge;
  if (!charge || typeof charge === "string") {
    return null;
  }

  if (charge.disputed) {
    return "disputed";
  }

  if (charge.refunded || charge.amount_refunded >= earlyPrice.amount) {
    return "refunded";
  }

  return null;
}

export async function validateLicenseKey(licenseKey: string): Promise<LicenseValidation> {
  let payload: LicensePayload;
  try {
    payload = decodeLicenseKey(licenseKey);
  } catch (error) {
    return {
      ok: false,
      status: "invalid",
      reason: error instanceof Error ? error.message : "License is invalid",
    };
  }

  if (payload.stripePriceId !== getBlitzRecorderEarlyPriceId()) {
    return { ok: false, status: "wrong_product", reason: "License is for a different Stripe price" };
  }

  // Revocation lives in the license store (refund/dispute webhooks or manual
  // ops). A store outage falls back to the Stripe-only checks below.
  if (isLicenseStoreConfigured()) {
    const stored = await getLicense(payload.licenseId).catch(() => null);
    if (stored?.status === "revoked") {
      return {
        ok: false,
        status: "revoked",
        reason: stored.revokedReason
          ? `License was revoked (${stored.revokedReason})`
          : "License was revoked",
      };
    }

    const paymentIntentRevocation = payload.stripePaymentIntentId
      ? await getPaymentIntentRevocation(payload.stripePaymentIntentId).catch(() => null)
      : null;
    if (paymentIntentRevocation) {
      return {
        ok: false,
        status: "revoked",
        reason: `License was revoked (${paymentIntentRevocation.reason})`,
      };
    }
  }

  if (isManualSignedLicense(payload)) {
    return { ok: true, status: "active", payload };
  }

  const stripe = getStripe();
  const session = await stripe.checkout.sessions.retrieve(payload.stripeSessionId, {
    expand: ["line_items.data.price"],
  });

  try {
    assertPaidBlitzRecorderSession(session);
  } catch (error) {
    return {
      ok: false,
      status: "unpaid",
      reason: error instanceof Error ? error.message : "Payment is not active",
    };
  }

  const paymentRevocation = await paymentRevocationStatus(payload.stripePaymentIntentId);
  if (paymentRevocation === "refunded") {
    return { ok: false, status: "refunded", reason: "Payment was refunded" };
  }
  if (paymentRevocation === "disputed") {
    return { ok: false, status: "revoked", reason: "Payment was disputed" };
  }

  // Backfill the store for licenses claimed before the webhook/store existed.
  // The upsert never touches `status`, so it cannot resurrect a revocation.
  if (isLicenseStoreConfigured()) {
    await upsertLicenseWithContext(payload, storeContextForSession(session)).catch(() => {});
  }

  return { ok: true, status: "active", payload };
}

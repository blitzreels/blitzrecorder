import crypto from "node:crypto";
import type Stripe from "stripe";
import { earlyPrice, getBlitzRecorderEarlyPriceId, getStripe } from "@/lib/payments";
import {
  getPaymentIntentRevocation,
  getLicense,
  isLicenseStoreConfigured,
  upsertLicenseWithContext,
} from "@/lib/license-store";

export const FREE_LICENSE_PRICE_ID = "free";
const FREE_LICENSE_EPOCH = 1_757_376_000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export type LicensePlan = "early_lifetime_2026" | "free_2026";

export type LicensePayload = {
  version: 1;
  app: "blitzrecorder";
  licenseId: string;
  kind: "early_lifetime";
  plan: LicensePlan;
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

/**
 * A checkout session that will never yield a license (another product, not
 * paid yet, unknown session). Callers treat it as a skip, not a failure.
 */
export class CheckoutSessionNotEligible extends Error {}

/** "required" lets a store outage fail the claim so the webhook is retried. */
export type LicenseStoreWrite = "required" | "best_effort";

const VALIDATION_CACHE_MS = 5 * 60 * 1000;
const VALIDATION_CACHE_MAX = 5_000;
const validationCache = new Map<string, { payload: LicensePayload; expiresAt: number }>();

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

function isOfflineIssuedLicense(payload: LicensePayload): boolean {
  const session = payload.stripeSessionId;
  const offlineSession = session.startsWith("manual_") || session.startsWith("free_");
  return (
    payload.kind === "early_lifetime" &&
    payload.grandfathered === true &&
    offlineSession &&
    payload.stripeCustomerId === null &&
    payload.stripePaymentIntentId === null
  );
}

export function normalizeLicenseEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function isValidLicenseEmail(email: string): boolean {
  return EMAIL_RE.test(normalizeLicenseEmail(email));
}

export function createFreeLicenseGrant(email: string): string {
  const normalized = normalizeLicenseEmail(email);
  const body = base64url(normalized);
  return `BRG1.${body}.${hmac(`grant:${normalized}`)}`;
}

export function emailFromFreeLicenseGrant(grant: string): string {
  const key = grant.trim();
  const parts = key.split(".");
  if (parts.length !== 3 || parts[0] !== "BRG1" || !parts[1] || !parts[2]) {
    throw new Error("License grant is invalid");
  }
  const email = normalizeLicenseEmail(unbase64url(parts[1]));
  const expected = hmac(`grant:${email}`);
  const given = Buffer.from(parts[2]);
  const wanted = Buffer.from(expected);
  if (given.length !== wanted.length || !crypto.timingSafeEqual(given, wanted)) {
    throw new Error("License grant is invalid");
  }
  if (!isValidLicenseEmail(email)) {
    throw new Error("License grant email is invalid");
  }
  return email;
}

function freeSessionId(email: string): string {
  return `free_${hmac(`session:${normalizeLicenseEmail(email)}`).slice(0, 32)}`;
}

export async function issueFreeLicense({
  email,
  attribution,
}: {
  email: string;
  attribution: Record<string, string>;
}): Promise<ClaimedLicense> {
  const normalized = normalizeLicenseEmail(email);
  if (!isValidLicenseEmail(normalized)) {
    throw new Error("Enter a valid email address.");
  }

  const sessionId = freeSessionId(normalized);
  const payload: LicensePayload = {
    version: 1,
    app: "blitzrecorder",
    licenseId: stableLicenseId(sessionId),
    kind: "early_lifetime",
    plan: "free_2026",
    maxDevices: null,
    grandfathered: true,
    email: normalized,
    stripeSessionId: sessionId,
    stripeCustomerId: null,
    stripePaymentIntentId: null,
    stripePriceId: FREE_LICENSE_PRICE_ID,
    issuedAt: FREE_LICENSE_EPOCH,
  };

  // Free keys verify offline; the row only records the signup.
  if (isLicenseStoreConfigured()) {
    await upsertLicenseWithContext(payload, {
      stripeLivemode: false,
      stripeAccountId: null,
      attribution,
    }).catch((error) => logStoreFailure({ action: "record free license", error }));
  }

  return {
    licenseId: payload.licenseId,
    email: normalized,
    licenseKey: signPayload(payload),
    payload,
  };
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
    throw new CheckoutSessionNotEligible("Checkout session is not a one-time payment");
  }
  if (session.payment_status !== "paid") {
    throw new CheckoutSessionNotEligible("Checkout session is not paid");
  }
  if (!sessionPriceIds(session).includes(priceId)) {
    throw new CheckoutSessionNotEligible("Checkout session is not for the BlitzRecorder lifetime license");
  }
}

function isStripeResourceMissing(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "resource_missing";
}

function logStoreFailure({ action, error }: { action: string; error: unknown }): void {
  console.error(`License store: failed to ${action}`, error instanceof Error ? error.message : error);
}

function sessionAttribution(session: Stripe.Checkout.Session): Record<string, string> {
  return Object.fromEntries(
    Object.entries(session.metadata ?? {}).filter((entry): entry is [string, string] =>
      typeof entry[1] === "string",
    ),
  );
}

function storeContextForSession({
  session,
  stripeAccountId,
}: {
  session: Stripe.Checkout.Session;
  stripeAccountId: string | null;
}) {
  const attribution = sessionAttribution(session);
  return {
    stripeLivemode: session.livemode,
    stripeAccountId:
      stripeAccountId ??
      attribution.stripe_account_id ??
      process.env.STRIPE_ACCOUNT_ID ??
      null,
    attribution,
  };
}

export async function claimLicenseForCheckoutSession({
  sessionId,
  stripeAccountId,
  storeWrite,
}: {
  sessionId: string;
  stripeAccountId: string | null;
  storeWrite: LicenseStoreWrite;
}): Promise<ClaimedLicense> {
  const stripe = getStripe();
  const priceId = getBlitzRecorderEarlyPriceId();
  const session = await stripe.checkout.sessions
    .retrieve(sessionId, { expand: ["line_items.data.price", "payment_intent", "customer"] })
    .catch((error: unknown) => {
      if (isStripeResourceMissing(error)) {
        throw new CheckoutSessionNotEligible("Checkout session was not found");
      }
      throw error;
    });

  assertPaidBlitzRecorderSession(session);

  const customerEmail =
    typeof session.customer !== "string" && session.customer && !("deleted" in session.customer)
      ? session.customer.email
      : null;
  const email = session.customer_details?.email ?? customerEmail;

  if (!email) {
    throw new CheckoutSessionNotEligible("Checkout session does not include a customer email");
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

  // The upsert is keyed by license id (derived from the session id), so a
  // retried webhook is idempotent. Customer-facing claims stay best effort:
  // the key is valid without the row and the webhook records it.
  if (isLicenseStoreConfigured()) {
    const write = upsertLicenseWithContext(payload, storeContextForSession({ session, stripeAccountId }));
    if (storeWrite === "required") {
      await write;
    } else {
      await write.catch((error) => logStoreFailure({ action: "record claimed license", error }));
    }
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

  const offline = isOfflineIssuedLicense(payload);
  // A missing price id is a server misconfiguration, so it throws (500)
  // rather than telling the app the license is invalid.
  if (!offline && payload.stripePriceId !== getBlitzRecorderEarlyPriceId()) {
    return { ok: false, status: "wrong_product", reason: "License is for a different Stripe price" };
  }

  // Revocation lives in the license store (refund/dispute webhooks or manual
  // ops). A store outage falls back to the Stripe-only checks below.
  if (isLicenseStoreConfigured()) {
    const stored = await getLicense(payload.licenseId).catch((error) => {
      logStoreFailure({ action: "read license", error });
      return null;
    });
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
      ? await getPaymentIntentRevocation(payload.stripePaymentIntentId).catch((error) => {
          logStoreFailure({ action: "read payment revocation", error });
          return null;
        })
      : null;
    if (paymentIntentRevocation) {
      return {
        ok: false,
        status: "revoked",
        reason: `License was revoked (${paymentIntentRevocation.reason})`,
      };
    }
  }

  // Checked after the store, so a refund or dispute recorded there is never hidden by a cached result;
  // the cache only spares the Stripe calls below.
  const cacheKey = licenseKeyHash(licenseKey);
  const cached = validationCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) {
    return { ok: true, status: "active", payload: cached.payload };
  }
  validationCache.delete(cacheKey);

  if (offline) {
    return cacheActiveValidation({ cacheKey, payload });
  }

  const stripe = getStripe();
  const session = await stripe.checkout.sessions.retrieve(payload.stripeSessionId, {
    expand: ["line_items.data.price"],
  });

  try {
    assertPaidBlitzRecorderSession(session);
  } catch (error) {
    if (!(error instanceof CheckoutSessionNotEligible)) {
      throw error;
    }
    return { ok: false, status: "unpaid", reason: error.message };
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
    await upsertLicenseWithContext(payload, storeContextForSession({ session, stripeAccountId: null }))
      .catch((error) => logStoreFailure({ action: "backfill license", error }));
  }

  return cacheActiveValidation({ cacheKey, payload });
}

export function licenseKeyHash(licenseKey: string): string {
  return crypto.createHash("sha256").update(licenseKey.trim()).digest("hex");
}

// Only active results are cached; failures always re-check, so a Stripe
// outage is never remembered as an invalid license.
function cacheActiveValidation({
  cacheKey,
  payload,
}: {
  cacheKey: string;
  payload: LicensePayload;
}): LicenseValidation {
  if (validationCache.size >= VALIDATION_CACHE_MAX) {
    const oldest = validationCache.keys().next().value;
    if (oldest !== undefined) validationCache.delete(oldest);
  }
  validationCache.set(cacheKey, { payload, expiresAt: Date.now() + VALIDATION_CACHE_MS });
  return { ok: true, status: "active", payload };
}

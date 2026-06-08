import Stripe from "stripe";

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing ${name}`);
  }
  return value;
}

export function getBlitzRecorderProductId(): string {
  return requiredEnv("BLITZRECORDER_STRIPE_PRODUCT_ID");
}

export function getBlitzRecorderEarlyPriceId(): string {
  return requiredEnv("BLITZRECORDER_STRIPE_PRICE_ID");
}

export const earlyPrice = {
  name: "BlitzRecorder Lifetime License",
  amount: 3900,
  regularAmount: 7900,
  currency: "usd",
  description:
    "Unlock iPhone camera recording, 4K export, 60 fps export, your personal Macs, and updates through beta and v1.",
  display: "$39",
  regularDisplay: "$79",
  get productId() {
    return getBlitzRecorderProductId();
  },
  get priceId() {
    return getBlitzRecorderEarlyPriceId();
  },
};

let stripeClient: Stripe | null = null;

export function getStripe(): Stripe {
  const secretKey = process.env.STRIPE_SECRET_KEY;
  if (!secretKey) {
    throw new Error("Missing STRIPE_SECRET_KEY");
  }

  stripeClient ??= new Stripe(secretKey);
  return stripeClient;
}

export function getSiteUrl(requestUrl?: string): string {
  const configured = process.env.NEXT_PUBLIC_SITE_URL ?? process.env.SITE_URL;
  if (configured) {
    return configured.replace(/\/$/, "");
  }

  if (requestUrl) {
    const url = new URL(requestUrl);
    return `${url.protocol}//${url.host}`;
  }

  return "http://localhost:3000";
}

export async function createEarlyPriceCheckoutSession({
  requestUrl,
  email,
  attributionMetadata,
}: {
  requestUrl: string;
  email?: string | null;
  attributionMetadata?: Record<string, string>;
}): Promise<Stripe.Checkout.Session> {
  const siteUrl = getSiteUrl(requestUrl);
  const stripe = getStripe();
  const priceId = getBlitzRecorderEarlyPriceId();
  const metadata = {
    app: "blitzrecorder",
    product: "early_lifetime",
    license_kind: "lifetime",
    license_plan: "early_lifetime_2026",
    max_devices: "unlimited_personal_macs",
    grandfathered: "true",
    ...(process.env.STRIPE_ACCOUNT_ID ? { stripe_account_id: process.env.STRIPE_ACCOUNT_ID } : {}),
    ...attributionMetadata,
  };

  return stripe.checkout.sessions.create({
    mode: "payment",
    customer_email: email || undefined,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${siteUrl}/license/claim?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${siteUrl}/?checkout=cancel#pricing`,
    submit_type: "pay",
    custom_text: {
      submit: {
        message:
          "One-time $39 beta lifetime license, planned to become $79 after launch. Unlocks iPhone camera recording, 4K export, 60 fps export, and updates through beta and v1.",
      },
      after_submit: {
        message:
          "After payment, you will claim a license key and can open BlitzRecorder to activate it.",
      },
    },
    allow_promotion_codes: true,
    billing_address_collection: "auto",
    automatic_tax: { enabled: process.env.STRIPE_AUTOMATIC_TAX === "true" },
    metadata,
    payment_intent_data: { metadata },
  });
}

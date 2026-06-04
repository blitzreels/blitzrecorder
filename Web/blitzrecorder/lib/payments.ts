import Stripe from "stripe";

export const BLITZRECORDER_PRODUCT_ID = "prod_UdcIOAn7zHpoGN";
export const BLITZRECORDER_EARLY_PRICE_ID =
  process.env.BLITZRECORDER_STRIPE_PRICE_ID ?? "price_1TeL4LRibTVfQOaErwsdVjH9";

export const earlyPrice = {
  name: "BlitzRecorder Early Price",
  amount: 3900,
  currency: "usd",
  display: "$39",
  productId: BLITZRECORDER_PRODUCT_ID,
  priceId: BLITZRECORDER_EARLY_PRICE_ID,
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
  const metadata = {
    app: "blitzrecorder",
    product: "early_lifetime",
    license_kind: "lifetime",
    ...attributionMetadata,
  };

  return stripe.checkout.sessions.create({
    mode: "payment",
    customer_email: email || undefined,
    line_items: [{ price: BLITZRECORDER_EARLY_PRICE_ID, quantity: 1 }],
    success_url: `${siteUrl}/license/claim?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${siteUrl}/#pricing`,
    allow_promotion_codes: true,
    billing_address_collection: "auto",
    automatic_tax: { enabled: process.env.STRIPE_AUTOMATIC_TAX === "true" },
    metadata,
    payment_intent_data: { metadata },
  });
}

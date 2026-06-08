import { NextResponse } from "next/server";
import type Stripe from "stripe";
import { getStripe } from "@/lib/payments";
import { claimLicenseForCheckoutSession } from "@/lib/licenses";
import {
  isLicenseStoreConfigured,
  revokeLicenseByPaymentIntent,
} from "@/lib/license-store";

export const runtime = "nodejs";

function paymentIntentId(
  value: string | Stripe.PaymentIntent | null | undefined,
): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!signature || !webhookSecret) {
    return NextResponse.json({ error: "Missing Stripe webhook configuration" }, { status: 400 });
  }

  const body = await request.text();

  let event: Stripe.Event;
  try {
    event = getStripe().webhooks.constructEvent(body, signature, webhookSecret);
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Invalid Stripe webhook" },
      { status: 400 },
    );
  }

  // Without a store the stateless flow stands alone: validation re-checks
  // Stripe live, so there is nothing to record here.
  if (!isLicenseStoreConfigured()) {
    return NextResponse.json({ received: true });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object;
        // claimLicense re-fetches and asserts paid + BlitzRecorder price, and
        // upserts into the store. A session for another product or an unpaid
        // async method just skips.
        await claimLicenseForCheckoutSession(session.id, {
          stripeAccountId: event.account ?? null,
        }).catch(() => null);
        break;
      }
      case "charge.refunded": {
        const pi = paymentIntentId(event.data.object.payment_intent);
        if (pi) {
          await revokeLicenseByPaymentIntent(pi, "refunded");
        }
        break;
      }
      case "charge.dispute.created": {
        const pi = paymentIntentId(event.data.object.payment_intent);
        if (pi) {
          await revokeLicenseByPaymentIntent(pi, "disputed");
        }
        break;
      }
      default:
        break;
    }
  } catch (error) {
    // Store hiccup: non-2xx so Stripe retries the event later.
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Webhook handler failed" },
      { status: 500 },
    );
  }

  return NextResponse.json({ received: true });
}

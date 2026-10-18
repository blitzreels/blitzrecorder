import type Stripe from "stripe";
import { getStripe } from "../payments";
import { hostingPool } from "./db";
import { HostingError, type HostingAccount } from "./model";

/** `unavailable`: Stripe could not be reached, so the page shows billing access without details. */
export type SubscriptionState = "none" | "active" | "canceling" | "past_due" | "ended" | "unavailable";

export type SubscriptionView = {
  state: SubscriptionState;
  /** Next renewal while active, or the last day of access while canceling or ended. */
  periodEnd: string | null;
  card: { brand: string; last4: string; expMonth: number; expYear: number } | null;
  invoices: InvoiceRow[];
};

export type InvoiceRow = {
  id: string;
  number: string | null;
  date: string;
  amount: number;
  currency: string;
  status: string;
  url: string | null;
};

type StripeIDs = { customer: string | null; subscription: string | null };

async function stripeIDs(account: HostingAccount): Promise<StripeIDs> {
  const row = (await hostingPool().query<{ stripe_customer_id: string | null; stripe_subscription_id: string | null }>(
    "SELECT stripe_customer_id, stripe_subscription_id FROM hosting_accounts WHERE id=$1", [account.id])).rows[0];
  return { customer: row?.stripe_customer_id ?? null, subscription: row?.stripe_subscription_id ?? null };
}

function periodEnd(subscription: Stripe.Subscription): number | null {
  const ends = subscription.items.data.map((item) => item.current_period_end);
  return ends.length ? Math.max(...ends) : null;
}

function stateOf(subscription: Stripe.Subscription): SubscriptionState {
  if (subscription.status === "active" || subscription.status === "trialing") {
    return subscription.cancel_at_period_end || subscription.cancel_at ? "canceling" : "active";
  }
  if (subscription.status === "canceled" || subscription.status === "incomplete_expired") return "ended";
  return "past_due";
}

function cardOf(method: string | Stripe.PaymentMethod | null | undefined): SubscriptionView["card"] {
  if (!method || typeof method === "string" || !method.card) return null;
  return { brand: method.card.brand, last4: method.card.last4 ?? "", expMonth: method.card.exp_month, expYear: method.card.exp_year };
}

const iso = (seconds: number) => new Date(seconds * 1000).toISOString();

/** Reads the plan straight from Stripe so cancel and resume show up before the webhook lands. */
export async function subscriptionView(account: HostingAccount): Promise<SubscriptionView> {
  try {
    return await readSubscription(account);
  } catch (error) {
    console.error("Hosting subscription lookup failed", error instanceof Error ? error.name : "Unknown error");
    return { state: "unavailable", periodEnd: null, card: null, invoices: [] };
  }
}

async function readSubscription(account: HostingAccount): Promise<SubscriptionView> {
  const ids = await stripeIDs(account);
  if (!ids.customer) return { state: "none", periodEnd: null, card: null, invoices: [] };
  const stripe = getStripe();
  const [subscription, customer, invoices] = await Promise.all([
    ids.subscription ? stripe.subscriptions.retrieve(ids.subscription, { expand: ["default_payment_method"] }) : null,
    stripe.customers.retrieve(ids.customer, { expand: ["invoice_settings.default_payment_method"] }),
    stripe.invoices.list({ customer: ids.customer, limit: 12 }),
  ]);
  const customerMethod = customer.deleted ? null : customer.invoice_settings.default_payment_method;
  const cancelAt = subscription?.cancel_at ?? null;
  const end = subscription ? cancelAt ?? periodEnd(subscription) : null;
  return {
    state: subscription ? stateOf(subscription) : "none",
    periodEnd: end ? iso(subscription?.status === "canceled" && subscription.ended_at ? subscription.ended_at : end) : null,
    card: cardOf(subscription?.default_payment_method) ?? cardOf(customerMethod),
    invoices: invoices.data.filter((invoice) => invoice.status !== "draft").map((invoice) => ({
      id: invoice.id ?? invoice.number ?? String(invoice.created),
      number: invoice.number,
      date: iso(invoice.created),
      amount: invoice.amount_paid || invoice.amount_due,
      currency: invoice.currency,
      status: invoice.status ?? "open",
      url: invoice.hosted_invoice_url ?? null,
    })),
  };
}

/** Cancel at the end of the paid period, or undo that. Access never ends early. */
export async function setCancelAtPeriodEnd({ account, cancel }: { account: HostingAccount; cancel: boolean }): Promise<void> {
  const ids = await stripeIDs(account);
  if (!ids.subscription) throw new HostingError({ status: 409, message: "There is no subscription on this account." });
  const stripe = getStripe();
  const subscription = await stripe.subscriptions.retrieve(ids.subscription);
  const customer = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
  if (customer !== ids.customer) {
    throw new HostingError({ status: 409, message: "This subscription belongs to another account." });
  }
  if (subscription.status === "canceled" || subscription.status === "incomplete_expired") {
    throw new HostingError({ status: 409, message: "This subscription already ended. Subscribe again to restart it." });
  }
  const change: Stripe.SubscriptionUpdateParams = cancel || subscription.cancel_at_period_end
    ? { cancel_at_period_end: cancel }
    : { cancel_at: "" };
  await stripe.subscriptions.update(ids.subscription, change);
}

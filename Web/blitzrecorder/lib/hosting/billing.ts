import type Stripe from "stripe";
import { getStripe } from "../payments";
import { transaction } from "./db";
import { required } from "./model";
import { planStorageBytes } from "./account";

export function paidHostingPeriod({ subscription, priceID }: { subscription: Stripe.Subscription; priceID: string }): number | null {
  const invoice = subscription.latest_invoice;
  if (subscription.status !== "active" || subscription.pause_collection || !invoice || typeof invoice === "string" || invoice.status !== "paid") return null;
  const item = subscription.items.data.find((entry) => entry.price.id === priceID);
  return item && item.current_period_end > Date.now() / 1000 ? item.current_period_end : null;
}

export async function syncHostingBilling(event: Stripe.Event): Promise<void> {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return;
  let subscriptionID: string | null = null;
  if (["checkout.session.completed", "checkout.session.async_payment_succeeded"].includes(event.type)) {
    const session = event.data.object as Stripe.Checkout.Session;
    if (session.payment_status !== "paid" || !session.metadata?.blitzrecorder_hosting_account_id) return;
    subscriptionID = typeof session.subscription === "string" ? session.subscription : session.subscription?.id ?? null;
  } else if (["customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted",
    "customer.subscription.paused", "customer.subscription.resumed"].includes(event.type)) {
    const subscription = event.data.object as Stripe.Subscription;
    if (!subscription.metadata.blitzrecorder_hosting_account_id) return;
    subscriptionID = subscription.id;
  } else if (["invoice.paid", "invoice.payment_failed"].includes(event.type)) {
    const details = (event.data.object as Stripe.Invoice).parent?.subscription_details;
    if (!details?.metadata?.blitzrecorder_hosting_account_id) return;
    const reference = details.subscription;
    subscriptionID = typeof reference === "string" ? reference : reference?.id ?? null;
  }
  if (!subscriptionID) return;
  await transaction(async (db) => {
    await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`hosting:${subscriptionID}`]);
    const subscription = await getStripe().subscriptions.retrieve(subscriptionID, { expand: ["latest_invoice"] });
    const accountID = subscription.metadata.blitzrecorder_hosting_account_id;
    if (!accountID || !/^[a-f0-9-]{36}$/.test(accountID)) return;
    const storage = planStorageBytes();
    const priceID = required("HOSTING_STRIPE_PRICE_ID");
    const period = paidHostingPeriod({ subscription, priceID });
    const customer = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
    const account = (await db.query<{
      active_until: Date; stripe_subscription_id: string | null; stripe_customer_id: string | null;
    }>("SELECT active_until,stripe_subscription_id,stripe_customer_id FROM hosting_accounts WHERE id=$1 FOR UPDATE", [accountID])).rows[0];
    if (!account || (account.stripe_customer_id && account.stripe_customer_id !== customer)) {
      throw new Error("Hosting subscription is not linked to its account.");
    }
    if (account.stripe_subscription_id && account.stripe_subscription_id !== subscription.id
      && (period === null || account.active_until.getTime() > Date.now())) return;
    const updated = await db.query(
      `UPDATE hosting_accounts SET active_until=to_timestamp($2),storage_limit=$3,
       stripe_subscription_id=$4,stripe_customer_id=$5,
       inactive_since=CASE WHEN $2>0 THEN NULL ELSE COALESCE(inactive_since,now()) END WHERE id=$1`,
      [accountID, period ?? 0, storage, subscription.id, customer]);
    if (!updated.rowCount) throw new Error("Hosting subscription is not linked to its account.");
  });
}

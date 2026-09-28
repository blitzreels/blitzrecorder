import type { PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { getSiteUrl, getStripe } from "../payments";
import { hostingPool, transaction } from "./db";
import { HostingError, newAccessToken, required, tokenHash, type HostingAccount } from "./model";
import { HOSTING_PLAN } from "./plan";

export type HostingIdentity = { id: string; email: string };

export function planStorageBytes(): number {
  const storage = Number(process.env.HOSTING_PLAN_STORAGE_BYTES ?? HOSTING_PLAN.storageBytes);
  if (!Number.isSafeInteger(storage) || storage <= 0) throw new HostingError({ status: 503, message: "Video hosting is not configured yet." });
  return storage;
}

export async function connectAccount(identity: HostingIdentity) {
  return transaction((db) => connectAccountInTransaction({ ...identity, db }));
}

export async function connectAccountInTransaction(identity: HostingIdentity & { db: PoolClient }) {
  const storage = planStorageBytes();
  const token = newAccessToken();
  const connect = async (db: PoolClient) => {
    await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`hosting-email:${identity.email}`]);
    const existing = await db.query<HostingAccount>(
      "SELECT * FROM hosting_accounts WHERE lower(email)=$1 ORDER BY created_at LIMIT 2 FOR UPDATE", [identity.email]);
    if (existing.rows.length > 1) throw new HostingError({ status: 409, message: "Contact BlitzRecorder support to recover this account." });
    const result = existing.rows[0]
      ? await db.query<HostingAccount>("UPDATE hosting_accounts SET identity_id=$2,email=$3 WHERE id=$1 RETURNING *",
        [existing.rows[0].id, identity.id, identity.email])
      : await db.query<HostingAccount>(
        `INSERT INTO hosting_accounts (id,token_hash,identity_id,email,active_until,storage_limit)
         VALUES ($1,$2,$3,$4,to_timestamp(0),$5) RETURNING *`,
        [randomUUID(), tokenHash(newAccessToken()), identity.id, identity.email, storage]);
    const account = result.rows[0];
    await db.query("DELETE FROM hosting_connections WHERE account_id=$1 AND expires_at < now()", [account.id]);
    await db.query("INSERT INTO hosting_connections (token_hash,account_id) VALUES ($1,$2)", [tokenHash(token), account.id]);
    return { token, ...accountState(account) };
  };
  return connect(identity.db);
}

export function accountState(account: HostingAccount) {
  return { email: account.email, active: account.active_until.getTime() > Date.now(), activeUntil: account.active_until.toISOString(), storageLimit: Number(account.storage_limit) };
}

export async function disconnectAccount(request: Request) {
  const token = request.headers.get("authorization")?.slice(7) ?? "";
  await hostingPool().query("DELETE FROM hosting_connections WHERE token_hash=$1", [tokenHash(token)]);
  return { disconnected: true };
}

export async function billingURL(account: HostingAccount) {
  const stripe = getStripe();
  const site = getSiteUrl();
  if (!site.startsWith("https://") && !/^http:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(site)) {
    throw new HostingError({ status: 503, message: "Video hosting is not configured yet." });
  }
  return transaction(async (db) => {
    const row = (await db.query<{
      stripe_customer_id: string | null; stripe_subscription_id: string | null; active_until: Date;
      checkout_session_id: string | null; checkout_url: string | null; checkout_expires_at: Date | null;
      email: string | null;
    }>("SELECT * FROM hosting_accounts WHERE id=$1 FOR UPDATE", [account.id])).rows[0];
    let subscriptionEnded = false;
    if (row.stripe_customer_id && row.stripe_subscription_id) {
      const subscription = await stripe.subscriptions.retrieve(row.stripe_subscription_id);
      subscriptionEnded = ["canceled", "incomplete_expired"].includes(subscription.status);
      if (!subscriptionEnded) {
        const portal = await stripe.billingPortal.sessions.create({
          customer: row.stripe_customer_id, return_url: `${site}/hosting/complete`,
          configuration: required("HOSTING_STRIPE_PORTAL_CONFIGURATION_ID"),
        });
        return { url: portal.url };
      }
    }
    if (row.checkout_session_id && row.checkout_url && row.checkout_expires_at && row.checkout_expires_at.getTime() > Date.now()) {
      const previous = await stripe.checkout.sessions.retrieve(row.checkout_session_id);
      if (previous.status === "open") return { url: row.checkout_url };
      if (previous.status === "complete" && !subscriptionEnded) throw new HostingError({ status: 409, message: "Your payment is being confirmed. Return to the app and check your subscription." });
    }
    const metadata = { blitzrecorder_hosting_account_id: account.id };
    const priceID = required("HOSTING_STRIPE_PRICE_ID");
    const price = await stripe.prices.retrieve(priceID);
    if (!price.active || price.unit_amount !== HOSTING_PLAN.amount || price.currency !== HOSTING_PLAN.currency
      || price.recurring?.interval !== HOSTING_PLAN.interval || price.recurring.interval_count !== 1
      || price.tax_behavior !== HOSTING_PLAN.taxBehavior) {
      throw new HostingError({ status: 503, message: "The hosting plan is not available yet." });
    }
    const session = await stripe.checkout.sessions.create({
      mode: "subscription", line_items: [{ price: priceID, quantity: 1 }],
      automatic_tax: { enabled: process.env.STRIPE_AUTOMATIC_TAX === "true" },
      customer: row.stripe_customer_id ?? undefined,
      customer_email: row.stripe_customer_id ? undefined : row.email ?? undefined,
      client_reference_id: account.id, metadata, subscription_data: { metadata },
      integration_identifier: "blitzrecorder_hosting_qmzpxrta",
      branding_settings: { display_name: "BlitzRecorder", button_color: "#00e69b", border_style: "rounded" },
      custom_text: { submit: { message: "BlitzRecorder video hosting. Your local recordings and exports remain free." } },
      success_url: `${site}/hosting/complete`, cancel_url: `${site}/hosting/complete?cancelled=1`,
    }, { idempotencyKey: `hosting-checkout:${account.id}:${row.checkout_session_id ?? "first"}` });
    if (!session.url) throw new HostingError({ status: 503, message: "The subscription page could not be opened." });
    await db.query("UPDATE hosting_accounts SET checkout_session_id=$2,checkout_url=$3,checkout_expires_at=to_timestamp($4) WHERE id=$1",
      [account.id, session.id, session.url, session.expires_at]);
    return { url: session.url };
  });
}

import { randomUUID } from "node:crypto";
import { getSiteUrl, getStripe } from "../payments";
import { hostingPool, transaction } from "./db";
import { assertHostingEnabled, HostingError, newAccessToken, required, tokenHash, type HostingAccount } from "./model";
import { HOSTING_PLAN } from "./plan";

export type HostingIdentity = { id: string; email: string };

export async function verifyIdentity(request: Request): Promise<HostingIdentity> {
  assertHostingEnabled();
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length > 8192) {
    throw new HostingError({ status: 401, message: "Sign in with BlitzReels to connect video hosting." });
  }
  const response = await fetch("https://blitzreels.com/api/blitzrecorder/connection", {
    headers: { Authorization: authorization }, redirect: "error", cache: "no-store", signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new HostingError({ status: response.status >= 500 ? 503 : 401, message: "Reconnect your BlitzReels account to continue." });
  const data = await response.json();
  const user = data?.user;
  if (typeof user?.id !== "string" || !/^[A-Za-z0-9_-]{1,200}$/.test(user.id)
    || typeof user.email !== "string" || user.email.length > 320 || !user.email.includes("@")) {
    throw new HostingError({ status: 401, message: "Your account could not be verified." });
  }
  return { id: user.id, email: user.email };
}

export function planStorageBytes(): number {
  const storage = Number(process.env.HOSTING_PLAN_STORAGE_BYTES ?? HOSTING_PLAN.storageBytes);
  if (!Number.isSafeInteger(storage) || storage <= 0) throw new HostingError({ status: 503, message: "Video hosting is not configured yet." });
  return storage;
}

export async function connectAccount(identity: HostingIdentity) {
  const storage = planStorageBytes();
  const token = newAccessToken();
  const account = await transaction(async (db) => {
    const result = await db.query<HostingAccount>(
      `INSERT INTO hosting_accounts (id,token_hash,identity_id,email,active_until,storage_limit)
       VALUES ($1,$2,$3,$4,to_timestamp(0),$5)
       ON CONFLICT (identity_id) DO UPDATE SET email=EXCLUDED.email RETURNING id,active_until,storage_limit`,
      [randomUUID(), tokenHash(newAccessToken()), identity.id, identity.email, storage]);
    const account = result.rows[0];
    await db.query("DELETE FROM hosting_connections WHERE account_id=$1 AND expires_at < now()", [account.id]);
    await db.query("INSERT INTO hosting_connections (token_hash,account_id) VALUES ($1,$2)", [tokenHash(token), account.id]);
    return account;
  });
  return { token, ...accountState(account) };
}

export function accountState(account: HostingAccount) {
  return { active: account.active_until.getTime() > Date.now(), activeUntil: account.active_until.toISOString(), storageLimit: Number(account.storage_limit) };
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
      success_url: `${site}/hosting/complete`, cancel_url: `${site}/hosting/complete?cancelled=1`,
    }, { idempotencyKey: `hosting-checkout:${account.id}:${row.checkout_session_id ?? "first"}` });
    if (!session.url) throw new HostingError({ status: 503, message: "The subscription page could not be opened." });
    await db.query("UPDATE hosting_accounts SET checkout_session_id=$2,checkout_url=$3,checkout_expires_at=to_timestamp($4) WHERE id=$1",
      [account.id, session.id, session.url, session.expires_at]);
    return { url: session.url };
  });
}

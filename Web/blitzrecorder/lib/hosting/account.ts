import type { PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { setTimeout } from "node:timers/promises";
import { getSiteUrl, getStripe } from "../payments";
import { hostingPool, transaction } from "./db";
import { HostingError, newAccessToken, required, tokenHash, type HostingAccount } from "./model";
import { HOSTING_PLAN } from "./plan";
import { storedBytes, uploadedSeconds } from "./usage";

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

export async function accountForToken(token: string): Promise<HostingAccount | null> {
  const result = await hostingPool().query<HostingAccount>(
    `SELECT id, email, active_until, storage_limit FROM hosting_accounts WHERE token_hash = $1
     OR id IN (SELECT account_id FROM hosting_connections WHERE token_hash=$1 AND expires_at>now())`, [tokenHash(token)]);
  return result.rows[0] ?? null;
}

export function accountState(account: HostingAccount) {
  return { email: account.email, active: account.active_until.getTime() > Date.now(), activeUntil: account.active_until.toISOString(), storageLimit: Number(account.storage_limit) };
}

/** Ends every Mac and browser session, including the account's original token. */
export async function signOutEverywhere(account: HostingAccount) {
  await transaction(async (db) => {
    await db.query("DELETE FROM hosting_connections WHERE account_id=$1", [account.id]);
    await db.query("UPDATE hosting_accounts SET token_hash=$2 WHERE id=$1", [account.id, tokenHash(newAccessToken())]);
  });
}

export async function disconnectAccount({ request, account, body }: { request: Request; account: HostingAccount; body: unknown }) {
  if (body && typeof body === "object" && "everywhere" in body && body.everywhere === true) {
    await signOutEverywhere(account);
    return { disconnected: true, everywhere: true };
  }
  const token = request.headers.get("authorization")?.slice(7) ?? "";
  await hostingPool().query("DELETE FROM hosting_connections WHERE token_hash=$1", [tokenHash(token)]);
  return { disconnected: true, everywhere: false };
}

export async function activeSessionCount(account: HostingAccount): Promise<number> {
  const result = await hostingPool().query<{ count: string }>(
    "SELECT count(*) FROM hosting_connections WHERE account_id=$1 AND expires_at>now()", [account.id]);
  return Number(result.rows[0]?.count ?? 0);
}

export type AccountOverview = {
  email: string | null;
  /** Paid hosting is current; own-Cloudflare sharing works either way. */
  subscribed: boolean;
  activeUntil: string;
  storageLimit: number;
  storedBytes: number;
  uploadedSeconds: number;
  sessions: number;
};

export async function accountOverview(account: HostingAccount): Promise<AccountOverview> {
  const db = hostingPool();
  const [bytes, seconds, sessions] = await Promise.all([
    storedBytes({ db, accountID: account.id }), uploadedSeconds({ db, accountID: account.id }), activeSessionCount(account),
  ]);
  const state = accountState(account);
  return {
    email: account.email, subscribed: state.active, activeUntil: state.activeUntil, storageLimit: state.storageLimit,
    storedBytes: bytes, uploadedSeconds: seconds, sessions,
  };
}

type BillingRow = {
  stripe_customer_id: string | null; stripe_subscription_id: string | null; email: string | null;
  checkout_session_id: string | null; checkout_url: string | null; checkout_expires_at: Date | null;
};

async function billingRow(account: HostingAccount): Promise<BillingRow> {
  return (await hostingPool().query<BillingRow>(
    `SELECT stripe_customer_id,stripe_subscription_id,email,checkout_session_id,checkout_url,checkout_expires_at
     FROM hosting_accounts WHERE id=$1`, [account.id])).rows[0];
}

/**
 * `returnPath` is where Stripe sends people back: the app flow or the web dashboard.
 * Stripe is called with no database lock held; a short claim on the account makes concurrent clicks share one checkout.
 */
export async function billingURL({ account, returnPath }: { account: HostingAccount; returnPath: string }) {
  const stripe = getStripe();
  const site = getSiteUrl();
  if (!site.startsWith("https://") && !/^http:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(site)) {
    throw new HostingError({ status: 503, message: "Video hosting is not configured yet." });
  }
  const row = await billingRow(account);
  let subscriptionEnded = false;
  if (row.stripe_customer_id && row.stripe_subscription_id) {
    const subscription = await stripe.subscriptions.retrieve(row.stripe_subscription_id);
    subscriptionEnded = ["canceled", "incomplete_expired"].includes(subscription.status);
    if (!subscriptionEnded) {
      const portal = await stripe.billingPortal.sessions.create({
        customer: row.stripe_customer_id, return_url: `${site}${returnPath}`,
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
  const claimed = await hostingPool().query(
    `UPDATE hosting_accounts SET checkout_claimed_until=now()+interval '30 seconds'
     WHERE id=$1 AND checkout_session_id IS NOT DISTINCT FROM $2 AND (checkout_claimed_until IS NULL OR checkout_claimed_until<now())`,
    [account.id, row.checkout_session_id]);
  if (!claimed.rowCount) return { url: await concurrentCheckout({ account, previous: row.checkout_session_id }) };
  try {
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
      success_url: `${site}${returnPath}`, cancel_url: `${site}${returnPath}?cancelled=1`,
    }, { idempotencyKey: `hosting-checkout:${account.id}:${returnPath}:${row.checkout_session_id ?? "first"}` });
    if (!session.url) throw new HostingError({ status: 503, message: "The subscription page could not be opened." });
    await hostingPool().query(
      `UPDATE hosting_accounts SET checkout_session_id=$2,checkout_url=$3,checkout_expires_at=to_timestamp($4),checkout_claimed_until=NULL
       WHERE id=$1`, [account.id, session.id, session.url, session.expires_at]);
    return { url: session.url };
  } catch (error) {
    await hostingPool().query("UPDATE hosting_accounts SET checkout_claimed_until=NULL WHERE id=$1", [account.id]);
    throw error;
  }
}

/** Another request is creating the checkout: wait for its link without holding a connection. */
async function concurrentCheckout({ account, previous }: { account: HostingAccount; previous: string | null }): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    await setTimeout(500);
    const row = await billingRow(account);
    if (row.checkout_session_id !== previous && row.checkout_url) return row.checkout_url;
  }
  throw new HostingError({ status: 409, message: "The subscription page is still opening. Try again in a moment." });
}

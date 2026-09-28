import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { accountState, billingURL, connectAccount, verifyIdentity } from "../../lib/hosting/account";
import { authenticate } from "../../lib/hosting/service";
import { hostingPool } from "../../lib/hosting/db";
import { getStripe } from "../../lib/payments";
import type Stripe from "stripe";

const database = process.env.HOSTING_TEST_DATABASE_URL;
const integration = database ? test : test.skip;
const schema = `hosting_identity_test_${randomUUID().replaceAll("-", "")}`;
let admin: Pool;

test.before(async () => {
  if (!database) return;
  assert.ok(["localhost", "127.0.0.1"].includes(new URL(database).hostname));
  admin = new Pool({ connectionString: database });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const scoped = new URL(database);
  scoped.searchParams.set("options", `-c search_path=${schema}`);
  process.env.HOSTING_DATABASE_URL = scoped.href;
  process.env.BLITZRECORDER_HOSTING_ENABLED = "true";
  process.env.HOSTING_PLAN_STORAGE_BYTES = String(1024 ** 3);
  process.env.HOSTING_STRIPE_PRICE_ID = "test-hosting-price";
  process.env.STRIPE_SECRET_KEY = "test-placeholder";
  process.env.NEXT_PUBLIC_SITE_URL = "https://hosting.test";
  for (const file of ["001-hosting.sql", "002-hosting-details.sql", "003-hosting-accounts.sql", "004-hosting-usage.sql"]) {
    await hostingPool().query(await readFile(new URL(`../../migrations/${file}`, import.meta.url), "utf8"));
  }
});

test.after(async () => {
  if (!database) return;
  await hostingPool().end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
});

integration("two devices reconnect to one unpaid account without revoking each other", async () => {
  const identity = { id: randomUUID(), email: "owner@example.test" };
  const [first, second] = await Promise.all([connectAccount(identity), connectAccount(identity)]);
  assert.equal(first.active, false);
  assert.equal(second.active, false);
  assert.notEqual(first.token, second.token);
  const request = (token: string) => new Request("https://hosting.test", { headers: { Authorization: `Bearer ${token}` } });
  const a = await authenticate(request(first.token));
  const b = await authenticate(request(second.token));
  assert.equal(a.id, b.id);
  assert.equal(accountState(a).storageLimit, 1024 ** 3);
  assert.equal(Number((await hostingPool().query("SELECT count(*) FROM hosting_accounts WHERE identity_id=$1", [identity.id])).rows[0].count), 1);
});

integration("identity is verified with the fixed provider and redirects cannot forward the bearer token", async (t) => {
  const upstream = t.mock.method(globalThis, "fetch", async (url: string | URL | Request, options?: RequestInit) => {
    assert.equal(url, "https://blitzreels.com/api/blitzrecorder/connection");
    assert.equal(options?.redirect, "error");
    return Response.json({ user: { id: "valid-user", email: "owner@example.test" } });
  });
  const identity = await verifyIdentity(new Request("https://hosting.test", { headers: { Authorization: "Bearer test-upstream-token" } }));
  assert.deepEqual(identity, { id: "valid-user", email: "owner@example.test" });
  upstream.mock.mockImplementation(async () => Response.json({ user: { id: "fake" } }, { status: 401 }));
  await assert.rejects(verifyIdentity(new Request("https://hosting.test", { headers: { Authorization: "Bearer invalid" } })), { status: 401 });
});

integration("concurrent subscribe actions reuse one checkout and never grant access from the return page", async (t) => {
  const connected = await connectAccount({ id: randomUUID(), email: "subscriber@example.test" });
  const account = await authenticate(new Request("https://hosting.test", { headers: { Authorization: `Bearer ${connected.token}` } }));
  const stripe = getStripe();
  t.mock.method(stripe.prices, "retrieve", async () => ({ active: true, unit_amount: 900, currency: "eur",
    tax_behavior: "exclusive", recurring: { interval: "month", interval_count: 1 } }) as Stripe.Price);
  const create = t.mock.method(stripe.checkout.sessions, "create", async (params: Stripe.Checkout.SessionCreateParams, options?: Stripe.RequestOptions) => {
    assert.equal(params.mode, "subscription");
    assert.equal(params.subscription_data?.metadata?.blitzrecorder_hosting_account_id, account.id);
    assert.equal(params.line_items?.[0]?.price, "test-hosting-price");
    assert.ok(options?.idempotencyKey);
    return { id: "checkout-test", url: "https://checkout.stripe.com/test", expires_at: Math.floor(Date.now() / 1000) + 3600 } as Stripe.Checkout.Session;
  });
  t.mock.method(stripe.checkout.sessions, "retrieve", async () => ({ status: "open" }) as Stripe.Checkout.Session);
  const [a, b] = await Promise.all([billingURL(account), billingURL(account)]);
  assert.equal(a.url, b.url);
  assert.equal(create.mock.callCount(), 1);
  const latest = (await hostingPool().query("SELECT active_until FROM hosting_accounts WHERE id=$1", [account.id])).rows[0];
  assert.equal(latest.active_until.getTime(), 0);
});

integration("checkout refuses a price that differs from the displayed hosting plan", async (t) => {
  const connected = await connectAccount({ id: randomUUID(), email: "pricing@example.test" });
  const account = await authenticate(new Request("https://hosting.test", { headers: { Authorization: `Bearer ${connected.token}` } }));
  const stripe = getStripe();
  t.mock.method(stripe.prices, "retrieve", async () => ({ active: true, unit_amount: 1900, currency: "eur",
    tax_behavior: "exclusive", recurring: { interval: "month", interval_count: 1 } }) as Stripe.Price);
  const checkout = t.mock.method(stripe.checkout.sessions, "create", async () => {
    throw new Error("A mismatched price must not create a checkout.");
  });
  await assert.rejects(billingURL(account), { status: 503 });
  assert.equal(checkout.mock.callCount(), 0);
});

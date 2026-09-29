import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { beginUpload, authenticate, ownedAsset, revokeAsset, sharedAsset, updateDetails, finishUpload } from "../../lib/hosting/service";
import { EMPTY_DETAILS } from "../../lib/hosting/details";
import { hostingPool } from "../../lib/hosting/db";
import { newAccessToken, tokenHash, parseUploadInput, reservationBytes, type HostingAccount } from "../../lib/hosting/model";
import { r2 } from "../../lib/hosting/r2";
import type Stripe from "stripe";
import { getStripe } from "../../lib/payments";
import { syncHostingBilling } from "../../lib/hosting/billing";
import { HOSTING_PLAN } from "../../lib/hosting/plan";
import { cleanupExpired } from "../../lib/hosting/processor";
import { stopSharingVideo } from "../../lib/hosting/web-session";

const database = process.env.HOSTING_TEST_DATABASE_URL;
const integration = database ? test : test.skip;
const schema = `hosting_test_${randomUUID().replaceAll("-", "")}`;
let admin: Pool;
let failJobNotification = false;

test.before(async () => {
  if (!database) return;
  assert.ok(["localhost", "127.0.0.1"].includes(new URL(database).hostname), "Hosting tests require a local database.");
  admin = new Pool({ connectionString: database });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const scoped = new URL(database);
  scoped.searchParams.set("options", `-c search_path=${schema}`);
  process.env.HOSTING_DATABASE_URL = scoped.href;
  process.env.BLITZRECORDER_HOSTING_ENABLED = "true";
  process.env.HOSTING_R2_ACCOUNT_ID = "test";
  process.env.HOSTING_R2_ACCESS_KEY_ID = "test";
  process.env.HOSTING_R2_SECRET_ACCESS_KEY = "test";
  process.env.HOSTING_R2_BUCKET = "test";
  await hostingPool().query(await readFile(new URL("../../migrations/001-hosting.sql", import.meta.url), "utf8"));
  await hostingPool().query(await readFile(new URL("../../migrations/002-hosting-details.sql", import.meta.url), "utf8"));
  await hostingPool().query(await readFile(new URL("../../migrations/003-hosting-accounts.sql", import.meta.url), "utf8"));
  await hostingPool().query(await readFile(new URL("../../migrations/004-hosting-usage.sql", import.meta.url), "utf8"));
  r2().middlewareStack.add(() => async (args) => {
    const value = args.input as { Key?: string };
    if (value.Key?.startsWith("hosting-jobs/") && failJobNotification) {
      failJobNotification = false;
      throw new Error("Notification interrupted");
    }
    return { response: {}, output: { $metadata: {}, UploadId: "test-upload", ContentLength: 1024,
      Metadata: { asset: value.Key?.split("/")[2] } } };
  }, {
    step: "initialize", name: "isolatedR2", priority: "high",
  });
});

test.after(async () => {
  if (!database) return;
  await hostingPool().end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
});

async function account({ limit, active }: { limit: number; active: boolean }): Promise<HostingAccount & { token: string }> {
  const token = newAccessToken();
  const result = await hostingPool().query<HostingAccount>(
    "INSERT INTO hosting_accounts (id,token_hash,active_until,storage_limit) VALUES ($1,$2,$3,$4) RETURNING *",
    [randomUUID(), tokenHash(token), new Date(Date.now() + (active ? 86400000 : -86400000)), limit]);
  return { ...result.rows[0], token };
}

const input = { title: "A recording", bytes: 1024, duration: 12, contentType: "video/mp4", requestKey: "a".repeat(20) };

integration("an interrupted worker notification retries without consuming the upload allowance twice", async () => {
  const owner = await account({ limit: 50_000_000_000, active: true });
  const upload = await beginUpload({ account: owner, body: input });
  failJobNotification = true;
  try {
    await assert.rejects(finishUpload({ account: owner, id: upload.id }), /Notification interrupted/);
    assert.equal((await finishUpload({ account: owner, id: upload.id })).status, "queued");
    const usage = await hostingPool().query("SELECT SUM(seconds) AS seconds FROM hosting_upload_usage WHERE account_id=$1", [owner.id]);
    assert.equal(Number(usage.rows[0].seconds), input.duration);
  } finally { failJobNotification = false; }
});

integration("upload allowance survives deletion, rejects concurrent overspend and expires after 30 days", async () => {
  const owner = await account({ limit: 50_000_000_000, active: true });
  await hostingPool().query("INSERT INTO hosting_upload_usage(asset_id,account_id,seconds) VALUES($1,$2,$3)",
    [randomUUID(), owner.id, HOSTING_PLAN.uploadSeconds - input.duration]);
  const a = await beginUpload({ account: owner, body: input });
  const b = await beginUpload({ account: owner, body: { ...input, requestKey: "b".repeat(20) } });
  const attempts = await Promise.allSettled([finishUpload({ account: owner, id: a.id }), finishUpload({ account: owner, id: b.id })]);
  assert.equal(attempts.filter(r => r.status === "fulfilled").length, 1);
  assert.equal((attempts.find(r => r.status === "rejected") as PromiseRejectedResult).reason.status, 429);
  const winner = attempts[0].status === "fulfilled" ? a : b;
  await finishUpload({ account: owner, id: winner.id });
  assert.equal(Number((await hostingPool().query("SELECT SUM(seconds) AS seconds FROM hosting_upload_usage WHERE account_id=$1", [owner.id])).rows[0].seconds), HOSTING_PLAN.uploadSeconds);
  await assert.rejects(beginUpload({ account: owner, body: { ...input, requestKey: "c".repeat(20) } }), { status: 429 });
  assert.equal(Number((await hostingPool().query("SELECT count(*) FROM hosting_assets WHERE account_id=$1", [owner.id])).rows[0].count), 2);
  await hostingPool().query("DELETE FROM hosting_assets WHERE id=$1", [winner.id]);
  const loser = winner.id === a.id ? b : a;
  await assert.rejects(finishUpload({ account: owner, id: loser.id }), { status: 429 });
  await hostingPool().query("UPDATE hosting_upload_usage SET created_at=now()-interval '31 days' WHERE account_id=$1", [owner.id]);
  assert.equal((await finishUpload({ account: owner, id: loser.id })).status, "queued");
});

integration("expired hosting preserves files for 30 days and does not clean active accounts", async () => {
  const owner = await account({ limit: 1024 ** 3, active: true });
  const asset = await beginUpload({ account: owner, body: input });
  await hostingPool().query("UPDATE hosting_accounts SET active_until=to_timestamp(0),inactive_since=now() WHERE id=$1", [owner.id]);
  await cleanupExpired();
  assert.ok(await ownedAsset({ account: owner, id: asset.id }));
  await hostingPool().query("UPDATE hosting_accounts SET active_until=now()+interval '1 day',inactive_since=now()-interval '31 days' WHERE id=$1", [owner.id]);
  await cleanupExpired();
  assert.ok(await ownedAsset({ account: owner, id: asset.id }));
  await hostingPool().query("UPDATE hosting_accounts SET active_until=now()-interval '31 days' WHERE id=$1", [owner.id]);
  await cleanupExpired();
  await assert.rejects(ownedAsset({ account: owner, id: asset.id }), { status: 404 });
});

integration("only the paid owner can attach bounded viewer metadata and revoked videos reject updates", async () => {
  const owner = await account({ limit: 1024 ** 3, active: true });
  const stranger = await account({ limit: 1024 ** 3, active: true });
  const asset = await beginUpload({ account: owner, body: input });
  const body = { ...EMPTY_DETAILS, summary: "A demo", transcript: [{ start: 1, end: 2, text: "Hello", speaker: null }], sourcePath: "/private/file" };
  await assert.rejects(updateDetails({ account: stranger, id: asset.id, body }), { status: 404 });
  await updateDetails({ account: owner, id: asset.id, body });
  const stored = await ownedAsset({ account: owner, id: asset.id });
  assert.equal(stored.viewer_details.summary, "A demo");
  assert.equal("sourcePath" in stored.viewer_details, false);
  await assert.rejects(updateDetails({ account: owner, id: asset.id, body: { ...body, chapters: [{ start: 99, title: "Invalid" }] } }), { status: 400 });
  await revokeAsset({ account: owner, id: asset.id });
  await assert.rejects(updateDetails({ account: owner, id: asset.id, body }), { status: 409 });
});

integration("stopping a share from the web only works for the owner and ends the public link", async () => {
  const owner = await account({ limit: 1024 ** 3, active: true });
  const stranger = await account({ limit: 1024 ** 3, active: true });
  const { id } = await beginUpload({ account: owner, body: { ...input, requestKey: "w".repeat(20) } });
  const { slug } = (await hostingPool().query<{ slug: string }>(
    "UPDATE hosting_assets SET status='ready' WHERE id=$1 RETURNING slug", [id])).rows[0];
  assert.equal(await stopSharingVideo({ account: stranger, slug }), false);
  assert.ok(await sharedAsset(slug));
  assert.equal(await stopSharingVideo({ account: owner, slug }), true);
  assert.equal(await sharedAsset(slug), null);
  assert.equal(await stopSharingVideo({ account: owner, slug }), false);
});

integration("concurrent uploads cannot overspend the account storage quota", async () => {
  const owner = await account({ limit: reservationBytes(parseUploadInput(input)) + 1, active: true });
  const outcomes = await Promise.allSettled([
    beginUpload({ account: owner, body: input }),
    beginUpload({ account: owner, body: { ...input, requestKey: "b".repeat(20) } }),
  ]);
  assert.equal(outcomes.filter((outcome) => outcome.status === "fulfilled").length, 1);
  assert.equal(outcomes.filter((outcome) => outcome.status === "rejected").length, 1);
  const rejected = outcomes.find((outcome) => outcome.status === "rejected") as PromiseRejectedResult;
  assert.equal(rejected.reason.status, 413);
});

integration("retried initialization creates one asset and rejects reused keys for another file", async () => {
  const owner = await account({ limit: 1024 ** 3, active: true });
  const [first, second] = await Promise.all([beginUpload({ account: owner, body: input }), beginUpload({ account: owner, body: input })]);
  assert.equal(first.id, second.id);
  await assert.rejects(beginUpload({ account: owner, body: { ...input, bytes: 2048 } }), { status: 409 });
});

integration("inactive accounts cannot upload and other owners cannot access a video", async () => {
  const inactive = await account({ limit: 1024 ** 3, active: false });
  await assert.rejects(beginUpload({ account: inactive, body: input }), { status: 402 });
  const owner = await account({ limit: 1024 ** 3, active: true });
  const asset = await beginUpload({ account: owner, body: input });
  await assert.rejects(ownedAsset({ account: inactive, id: asset.id }), { status: 404 });
  await assert.rejects(authenticate(new Request("http://localhost/api/hosting/assets")), { status: 401 });
  const signedIn = await authenticate(new Request("http://localhost/api/hosting/assets", { headers: { Authorization: `Bearer ${owner.token}` } }));
  assert.equal(signedIn.id, owner.id);
});

integration("revocation blocks playback before cleanup and keeps bytes reserved until deletion", async () => {
  const owner = await account({ limit: reservationBytes(parseUploadInput(input)) + 1, active: true });
  const asset = await beginUpload({ account: owner, body: input });
  await hostingPool().query("UPDATE hosting_assets SET status='ready' WHERE id=$1", [asset.id]);
  const stored = await ownedAsset({ account: owner, id: asset.id });
  assert.ok(await sharedAsset(stored.slug));
  await revokeAsset({ account: owner, id: asset.id });
  assert.equal(await sharedAsset(stored.slug), null);
  await assert.rejects(beginUpload({ account: owner, body: { ...input, requestKey: "z".repeat(20) } }), { status: 413 });
});

integration("subscription replacement survives delayed events from the old subscription", async (t) => {
  process.env.STRIPE_SECRET_KEY = "sk_test_hosting_fixture";
  process.env.HOSTING_STRIPE_PRICE_ID = "hosting-price";
  process.env.HOSTING_PLAN_STORAGE_BYTES = String(1024 ** 3);
  const owner = await account({ limit: 1024 ** 3, active: false });
  const period = Math.floor(Date.now() / 1000) + 86400;
  let subscription = {
    id: "old-subscription", customer: "fixture-customer", status: "active", pause_collection: null,
    metadata: { blitzrecorder_hosting_account_id: owner.id }, latest_invoice: { status: "paid" },
    items: { data: [{ price: { id: "hosting-price" }, current_period_end: period }] },
  } as unknown as Stripe.Subscription;
  t.mock.method(getStripe().subscriptions, "retrieve", async () => subscription as Stripe.Response<Stripe.Subscription>);
  const event = () => ({ type: "customer.subscription.updated", data: { object: subscription } }) as Stripe.Event;
  await syncHostingBilling(event());
  subscription = { ...subscription, status: "canceled" };
  const canceled = subscription;
  await syncHostingBilling(event());
  subscription = { ...subscription, id: "new-subscription", status: "active" };
  await syncHostingBilling(event());
  subscription = canceled;
  await syncHostingBilling(event());
  const row = (await hostingPool().query("SELECT active_until,stripe_subscription_id FROM hosting_accounts WHERE id=$1", [owner.id])).rows[0];
  assert.equal(row.stripe_subscription_id, "new-subscription");
  assert.ok(row.active_until.getTime() > Date.now());
  subscription = { ...subscription, id: "new-subscription", status: "past_due" };
  await syncHostingBilling(event());
  const revoked = (await hostingPool().query("SELECT active_until FROM hosting_accounts WHERE id=$1", [owner.id])).rows[0];
  assert.ok(revoked.active_until.getTime() < Date.now());
});

integration("unrelated subscriptions leave the existing app billing flow untouched", async (t) => {
  process.env.STRIPE_SECRET_KEY = "sk_test_hosting_fixture";
  const retrieve = t.mock.method(getStripe().subscriptions, "retrieve", async () => { throw new Error("Unexpected Stripe call"); });
  await syncHostingBilling({ type: "customer.subscription.updated", data: { object: { id: "unrelated", metadata: {} } } } as Stripe.Event);
  assert.equal(retrieve.mock.callCount(), 0);
});

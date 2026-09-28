import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { hostingPool } from "../../lib/hosting/db";
import { connectAccount } from "../../lib/hosting/account";
import { requestSignInCode, verifySignInCode, signInEmail } from "../../lib/hosting/sign-in";
import { authenticate } from "../../lib/hosting/service";
import { tokenHash } from "../../lib/hosting/model";

const database = process.env.HOSTING_TEST_DATABASE_URL;
const integration = database ? test : test.skip;
const schema = `hosting_sign_in_${randomUUID().replaceAll("-", "")}`;
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
  process.env.HOSTING_AUTH_SECRET = "test-secret-with-no-production-access";
  process.env.HOSTING_EMAIL_API_KEY = "test-email-key";
  process.env.HOSTING_EMAIL_FROM = "BlitzRecorder <accounts@blitzrecorder.com>";
  for (const file of ["001-hosting.sql", "002-hosting-details.sql", "003-hosting-accounts.sql", "004-hosting-usage.sql", "005-hosting-sign-in.sql"]) {
    await hostingPool().query(await readFile(new URL(`../../migrations/${file}`, import.meta.url), "utf8"));
  }
});

test.after(async () => {
  if (!database) return;
  await hostingPool().end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
});

function mail(t: test.TestContext) {
  const codes: string[] = [];
  const send = t.mock.method(globalThis, "fetch", async (url: string | URL | Request, options?: RequestInit) => {
    assert.equal(url, "https://api.resend.com/emails");
    assert.equal(options?.redirect, "error");
    const payload = JSON.parse(String(options?.body));
    assert.equal(payload.from, "BlitzRecorder <accounts@blitzrecorder.com>");
    assert.ok(!JSON.stringify(payload).includes("BlitzReels"));
    codes.push(payload.subject.match(/^\d{6}/)[0]);
    return Response.json({ id: randomUUID() });
  });
  return { codes, send };
}

function request(email: string) { return { body: { email }, network: randomUUID() }; }

test("sign-in accepts normalized email and rejects malformed input", () => {
  assert.equal(signInEmail({ email: " Owner@Example.com " }), "owner@example.com");
  for (const body of [null, {}, { email: "a" }, { email: ["a@b.test"] }, { email: "a@b.test\nBcc:other@x.test" }]) {
    assert.throws(() => signInEmail(body));
  }
});

integration("verified email creates a BlitzRecorder account and one-time code cannot be replayed", async (t) => {
  const provider = mail(t);
  const challenge = await requestSignInCode(request("NEW@example.test"));
  assert.equal(provider.send.mock.callCount(), 1);
  const row = (await hostingPool().query("SELECT * FROM hosting_sign_in_codes WHERE email=$1", ["new@example.test"])).rows[0];
  assert.equal(row.challenge_hash, tokenHash(challenge.challenge));
  assert.notEqual(row.code_hash, provider.codes[0]);
  const result = await verifySignInCode({ challenge: challenge.challenge, code: provider.codes[0] });
  assert.equal(result.email, "new@example.test");
  assert.equal(result.active, false);
  const account = await authenticate(new Request("https://hosting.test", { headers: { Authorization: `Bearer ${result.token}` } }));
  assert.equal(account.email, "new@example.test");
  await assert.rejects(verifySignInCode({ challenge: challenge.challenge, code: provider.codes[0] }), { status: 400 });
});

integration("wrong attempts persist and lock the challenge after five tries", async (t) => {
  const provider = mail(t);
  const challenge = await requestSignInCode(request("attempts@example.test"));
  const wrong = provider.codes[0] === "000000" ? "000001" : "000000";
  for (let i = 0; i < 5; i++) await assert.rejects(verifySignInCode({ challenge: challenge.challenge, code: wrong }), { status: 400 });
  await assert.rejects(verifySignInCode({ challenge: challenge.challenge, code: provider.codes[0] }), { status: 400 });
  const row = (await hostingPool().query("SELECT attempts FROM hosting_sign_in_codes WHERE challenge_hash=$1", [tokenHash(challenge.challenge)])).rows[0];
  assert.equal(row.attempts, 5);
});

integration("expired codes and concurrent replays cannot issue connections", async (t) => {
  const provider = mail(t);
  const expired = await requestSignInCode(request("expired@example.test"));
  await hostingPool().query("UPDATE hosting_sign_in_codes SET expires_at=now()-interval '1 second' WHERE challenge_hash=$1", [tokenHash(expired.challenge)]);
  await assert.rejects(verifySignInCode({ challenge: expired.challenge, code: provider.codes[0] }), { status: 400 });
  const live = await requestSignInCode(request("race@example.test"));
  const results = await Promise.allSettled([0, 1].map(() => verifySignInCode({ challenge: live.challenge, code: provider.codes[1] })));
  assert.equal(results.filter(result => result.status === "fulfilled").length, 1);
});

integration("concurrent requests send one email and never expose account existence", async (t) => {
  const provider = mail(t);
  const input = request("limit@example.test");
  const results = await Promise.allSettled([0, 1, 2].map(() => requestSignInCode(input)));
  assert.equal(provider.send.mock.callCount(), 1);
  assert.equal(results.filter(result => result.status === "fulfilled").length, 1);
});

integration("signing in by verified email preserves an existing hosting subscription", async (t) => {
  const previous = await connectAccount({ id: "legacy-identity", email: "existing@example.test" });
  const prior = await authenticate(new Request("https://hosting.test", { headers: { Authorization: `Bearer ${previous.token}` } }));
  await hostingPool().query("UPDATE hosting_accounts SET active_until=now()+interval '30 days' WHERE id=$1", [prior.id]);
  const provider = mail(t);
  const challenge = await requestSignInCode(request("existing@example.test"));
  const result = await verifySignInCode({ challenge: challenge.challenge, code: provider.codes[0] });
  assert.equal(result.active, true);
  const account = await authenticate(new Request("https://hosting.test", { headers: { Authorization: `Bearer ${result.token}` } }));
  assert.equal(account.id, prior.id);
});

integration("provider failure gives no false code-sent confirmation", async (t) => {
  t.mock.method(globalThis, "fetch", async () => Response.json({ error: "unavailable" }, { status: 503 }));
  await assert.rejects(requestSignInCode(request("unavailable@example.test")), { status: 503 });
});

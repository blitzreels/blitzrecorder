import test from "node:test";
import assert from "node:assert/strict";

test("validated MP4 delivery supports seeking and cannot bypass authorization or expose source paths", async (t) => {
  const { serve } = await import(new URL("../../hosting-worker/index.ts", import.meta.url).href);
  const key = "hosting/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/source";
  let authorized = true;
  let reads = 0;
  t.mock.method(globalThis, "fetch", async () => authorized
    ? Response.json({ prefix: null, files: [], ttl: 10, source: { key, bytes: 1000 } })
    : new Response(null, { status: 404 }));
  const original = Object.getOwnPropertyDescriptor(globalThis, "caches");
  Object.defineProperty(globalThis, "caches", { configurable: true, value: {
    default: { match: async () => undefined, put: async () => undefined },
  } });
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "caches", original);
    else Reflect.deleteProperty(globalThis, "caches");
  });
  const env = { SITE_ORIGIN: "https://site.test", DELIVERY_SECRET: "test-only", MEDIA: {
    get: async (objectKey: string, options: { range: { offset: number; length: number } }) => {
      reads++;
      assert.equal(objectKey, key);
      assert.deepEqual(options.range, { offset: 100, length: 100 });
      return { httpEtag: '"fixture"', body: new Uint8Array(100) };
    },
    head: async () => ({ httpEtag: '"fixture"' }),
  } };
  const ctx = { waitUntil: () => undefined };
  const response = await serve({ request: new Request("https://media.test/s/abcdefghijklmnopqrstuvwx/video.mp4", {
    headers: { Range: "bytes=100-199" },
  }), env, ctx });
  assert.equal(response.status, 206);
  assert.equal(response.headers.get("content-type"), "video/mp4");
  assert.equal(response.headers.get("content-range"), "bytes 100-199/1000");
  assert.equal((await response.arrayBuffer()).byteLength, 100);
  for (const file of ["source", "../source", "master.m3u8", "poster.jpg"]) {
    assert.equal((await serve({ request: new Request(`https://media.test/s/abcdefghijklmnopqrstuvwx/${file}`), env, ctx })).status, 404);
  }
  authorized = false;
  assert.equal((await serve({ request: new Request("https://media.test/s/abcdefghijklmnopqrstuvwx/video.mp4"), env, ctx })).status, 404);
  assert.equal(reads, 1);
});

test("edge authorization refuses redirects without forwarding the delivery secret", async (t) => {
  const modulePath = new URL("../../hosting-worker/index.ts", import.meta.url).href;
  const { serve } = await import(modulePath);
  const requests: RequestInit[] = [];
  t.mock.method(globalThis, "fetch", async (_input: unknown, init: RequestInit) => {
    requests.push(init);
    if (init.redirect === "error") throw new TypeError("Unsupported by Cloudflare Workers");
    return new Response(null, { status: 302, headers: { Location: "https://untrusted.test" } });
  });
  const original = Object.getOwnPropertyDescriptor(globalThis, "caches");
  Object.defineProperty(globalThis, "caches", { configurable: true, value: {
    default: { match: async () => undefined, put: async () => assert.fail("Redirects must not be cached") },
  } });
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "caches", original);
    else Reflect.deleteProperty(globalThis, "caches");
  });
  const response = await serve({
    request: new Request("https://media.test/s/abcdefghijklmnopqrstuvwx/master.m3u8"),
    env: { SITE_ORIGIN: "https://site.test", DELIVERY_SECRET: "test-only", MEDIA: {
      get: async () => assert.fail("Unauthorized media must not be read"),
    } },
    ctx: { waitUntil: () => assert.fail("Unauthorized media must not be cached") },
  });
  assert.equal(response.status, 404);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].redirect, "manual");
});

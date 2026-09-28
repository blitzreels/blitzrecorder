import test from "node:test";
import assert from "node:assert/strict";

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

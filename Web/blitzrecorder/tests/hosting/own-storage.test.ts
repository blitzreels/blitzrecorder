import test from "node:test";
import assert from "node:assert/strict";

type Stored = { data: Uint8Array<ArrayBuffer>; contentType: string };

function bucket() {
  const objects = new Map<string, Stored>();
  const uploads = new Map<string, Map<number, Uint8Array<ArrayBuffer>>>();
  const object = (key: string, stored: Stored, body: boolean, range?: { offset: number; length: number }) => {
    const data = range ? stored.data.slice(range.offset, range.offset + range.length) : stored.data;
    return { key, size: stored.data.length, httpEtag: `"${key}"`, range, ...(body ? { body: new Blob([data]).stream() } : {}) };
  };
  return {
    objects,
    head: async (key: string) => objects.has(key) ? object(key, objects.get(key)!, false) : null,
    get: async (key: string, options: { range: Headers }) => {
      const stored = objects.get(key);
      if (!stored) return null;
      const match = /^bytes=(\d+)-(\d*)$/.exec(options.range.get("Range") ?? "");
      const range = match ? { offset: Number(match[1]),
        length: (match[2] ? Number(match[2]) : stored.data.length - 1) - Number(match[1]) + 1 } : undefined;
      return object(key, stored, true, range);
    },
    put: async (key: string, body: ReadableStream, options: { httpMetadata: { contentType: string } }) => {
      objects.set(key, { data: new Uint8Array(await new Response(body).arrayBuffer()), contentType: options.httpMetadata.contentType });
    },
    createMultipartUpload: async (key: string) => { uploads.set(key, new Map()); return { uploadId: "upload-1" }; },
    resumeMultipartUpload: (key: string) => ({
      uploadPart: async (number: number, body: ReadableStream) => {
        uploads.get(key)!.set(number, new Uint8Array(await new Response(body).arrayBuffer()));
        return { partNumber: number, etag: `etag-${number}` };
      },
      complete: async (parts: { partNumber: number }[]) => {
        const chunks = parts.map((part) => uploads.get(key)!.get(part.partNumber)!);
        const data = new Uint8Array(await new Blob(chunks).arrayBuffer());
        objects.set(key, { data, contentType: "video/mp4" });
        return { size: data.length };
      },
    }),
    list: async ({ prefix }: { prefix: string }) => ({ objects: [...objects.keys()].filter((key) => key.startsWith(prefix)).map((key) => ({ key })) }),
    delete: async (keys: string[]) => { for (const key of keys) objects.delete(key); },
  };
}

const id = "0b5c2a7e-8a6f-4f1e-9a38-7b1c3d6e2f10";
const secret = "test-secret";

async function load() {
  const modulePath = new URL("../../../../Resources/CloudflareMediaWorker.mjs", import.meta.url).href;
  return import(modulePath) as Promise<{ serve: (input: { request: Request; env: unknown }) => Promise<Response> }>;
}

test("own storage worker uploads in parts, streams ranges, and deletes", async () => {
  const { serve } = await load();
  const MEDIA = bucket();
  const env = { MEDIA, UPLOAD_SECRET: secret };
  const auth = { Authorization: `Bearer ${secret}` };
  const call = (path: string, init: RequestInit = {}) => serve({ request: new Request(`https://w.test${path}`, init), env });

  assert.equal((await call(`/u/${id}/video.mp4?uploads`, { method: "POST" })).status, 401);
  const health = await (await call("/health", { headers: auth })).json();
  assert.deepEqual(health, { blitzrecorder: true, version: 2, upload: true });

  const { uploadId } = await (await call(`/u/${id}/video.mp4?uploads`, { method: "POST", headers: auth })).json();
  const parts = [];
  for (const [number, text] of [[1, "hello "], [2, "world"]] as const) {
    const response = await call(`/u/${id}/video.mp4?uploadId=${uploadId}&part=${number}`, {
      method: "PUT", headers: { ...auth, "Content-Length": String(text.length) }, body: text });
    parts.push(await response.json());
  }
  const done = await call(`/u/${id}/video.mp4?uploadId=${uploadId}`, { method: "POST", headers: auth, body: JSON.stringify({ parts }) });
  assert.deepEqual(await done.json(), { bytes: 11 });

  const head = await call(`/v/${id}/video.mp4`, { method: "HEAD" });
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("Content-Length"), "11");
  assert.equal(head.headers.get("Access-Control-Allow-Origin"), "*");

  const ranged = await call(`/v/${id}/video.mp4`, { headers: { Range: "bytes=6-10" } });
  assert.equal(ranged.status, 206);
  assert.equal(ranged.headers.get("Content-Range"), "bytes 6-10/11");
  assert.equal(await ranged.text(), "world");

  assert.equal((await call(`/v/${id}/poster.jpg`)).status, 404);
  assert.equal((await call(`/u/${id}`, { method: "DELETE" })).status, 401);
  assert.equal((await call(`/u/${id}`, { method: "DELETE", headers: auth })).status, 200);
  assert.equal(MEDIA.objects.size, 0);
});

test("own storage worker refuses paths outside videos", async () => {
  const { serve } = await load();
  const env = { MEDIA: bucket(), UPLOAD_SECRET: secret };
  for (const path of ["/v/../secret", `/v/${id}/other.txt`, "/u/not-an-id/video.mp4"]) {
    const response = await serve({ request: new Request(`https://w.test${path}`), env });
    assert.equal(response.status, 404, path);
  }
});

test("uploads accept only the BlitzRecorder media worker as own storage", async () => {
  const { parseUploadInput, mediaURL } = await import("../../lib/hosting/model");
  const base = { title: "Demo", bytes: 1024, duration: 3, contentType: "video/mp4", requestKey: "a".repeat(20),
    video: { width: 1920, height: 1080, frameRate: 30 } };
  assert.equal(parseUploadInput(base).mediaOrigin, null);
  const origin = "https://blitzrecorder-media.alice.workers.dev";
  assert.equal(parseUploadInput({ ...base, mediaOrigin: origin }).mediaOrigin, origin);
  for (const mediaOrigin of ["https://evil.example", "http://blitzrecorder-media.alice.workers.dev",
    "https://blitzrecorder-media.alice.workers.dev/", "https://other.alice.workers.dev"]) {
    assert.throws(() => parseUploadInput({ ...base, mediaOrigin }), /Reconnect your Cloudflare storage/, mediaOrigin);
  }
  const { video: _video, ...source } = base;
  assert.throws(() => parseUploadInput({ ...source, mediaOrigin: origin }), /Reconnect your Cloudflare storage/);
  assert.equal(mediaURL({ asset: { id, slug: "s".repeat(24), media_origin: origin }, path: "video.mp4" }), `${origin}/v/${id}/video.mp4`);
});

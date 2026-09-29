export interface Env {
  MEDIA: R2Bucket;
  SITE_ORIGIN: string;
  DELIVERY_SECRET: string;
}

type Delivery = {
  prefix: string | null; files: { path: string; bytes: number; contentType: string }[]; ttl: number;
  source?: { key: string; bytes: number } | null;
};

export function requestedRange({ header, size }: { header: string | null; size: number }): { offset: number; length: number } | null {
  if (!header) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) throw new Error("range");
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) throw new Error("range");
    return { offset: Math.max(0, size - suffix), length: Math.min(size, suffix) };
  }
  const offset = Number(match[1]);
  const end = match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
  if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(end) || offset >= size || end < offset) throw new Error("range");
  return { offset, length: end - offset + 1 };
}

async function delivery({ slug, env }: { slug: string; env: Env }): Promise<Delivery | null> {
  const origin = new URL(env.SITE_ORIGIN).origin;
  const cacheKey = new Request(`${origin}/__hosting-delivery/${slug}`);
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return cached.json<Delivery>();
  const response = await fetch(`${origin}/api/hosting/delivery/${slug}`, {
    headers: { Authorization: `Bearer ${env.DELIVERY_SECRET}` }, redirect: "manual", signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return null;
  const data = await response.json<Delivery>();
  if (data.prefix !== null && !/^hosting\/[a-f0-9-]{36}\/[a-f0-9-]{36}\/streams\/[a-f0-9-]{36}\/$/.test(data.prefix)) return null;
  if (data.source && (!/^hosting\/[a-f0-9-]{36}\/[a-f0-9-]{36}\/source$/.test(data.source.key)
    || !Number.isSafeInteger(data.source.bytes) || data.source.bytes <= 0)) return null;
  if (data.source && data.prefix && !data.prefix.startsWith(data.source.key.replace(/source$/, "streams/"))) return null;
  if (!data.prefix && !data.source) return null;
  await cache.put(cacheKey, Response.json(data, { headers: { "Cache-Control": "max-age=10" } }));
  return data;
}

export async function serve({ request, env, ctx }: { request: Request; env: Env; ctx: ExecutionContext }): Promise<Response> {
  const origin = new URL(env.SITE_ORIGIN).origin;
  const headers = new Headers({
    "Access-Control-Allow-Origin": origin, "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "Range, If-None-Match, If-Range", "Access-Control-Expose-Headers": "Content-Length, Content-Range, ETag",
    "Cross-Origin-Resource-Policy": "cross-origin", "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store",
  });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (!["GET", "HEAD"].includes(request.method)) return new Response(null, { status: 405, headers });
  const url = new URL(request.url);
  const match = /^\/s\/([A-Za-z0-9_-]{24})\/(.+)$/.exec(url.pathname);
  if (!match || match[2].includes("%") || match[2].includes("..")) return new Response(null, { status: 404, headers });
  const [, slug, filePath] = match;
  let allowed: Delivery | null;
  try { allowed = await delivery({ slug, env }); }
  catch (error) {
    console.error("Video delivery lookup failed", error instanceof Error ? error.message : "Unknown error");
    return new Response(null, { status: 503, headers });
  }
  const source = filePath === "video.mp4" ? allowed?.source : null;
  const file = source ? { path: filePath, bytes: source.bytes, contentType: "video/mp4" }
    : allowed?.prefix ? allowed.files.find((entry) => entry.path === filePath) : null;
  if (!allowed || !file) return new Response(null, { status: 404, headers });
  let range: ReturnType<typeof requestedRange>;
  try { range = requestedRange({ header: request.headers.get("Range"), size: file.bytes }); }
  catch {
    headers.set("Content-Range", `bytes */${file.bytes}`);
    return new Response(null, { status: 416, headers });
  }
  const key = source?.key ?? allowed.prefix + file.path;
  if (range && request.headers.has("If-Range")) {
    const current = await env.MEDIA.head(key);
    if (!current) return new Response(null, { status: 404, headers });
    if (request.headers.get("If-Range") !== current.httpEtag) range = null;
  }
  const cacheKey = new Request(`${url.origin}/__objects/${key}`);
  const cached = await caches.default.match(range ? new Request(cacheKey, { headers: { Range: request.headers.get("Range")! } }) : cacheKey);
  if (cached) {
    const result = new Headers(cached.headers);
    for (const [name, value] of headers) result.set(name, value);
    if (!range && request.headers.get("If-None-Match") === cached.headers.get("ETag")) return new Response(null, { status: 304, headers: result });
    return new Response(request.method === "HEAD" ? null : cached.body, { status: cached.status, headers: result });
  }
  const object = request.method === "HEAD" ? await env.MEDIA.head(key) : await env.MEDIA.get(key, range ? { range } : undefined);
  if (!object) return new Response(null, { status: 404, headers });
  headers.set("Content-Type", file.contentType);
  headers.set("ETag", object.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Length", String(range?.length ?? file.bytes));
  if (range) headers.set("Content-Range", `bytes ${range.offset}-${range.offset + range.length - 1}/${file.bytes}`);
  if (!range && request.headers.get("If-None-Match") === object.httpEtag) return new Response(null, { status: 304, headers });
  const body = "body" in object && request.method !== "HEAD" ? (object as R2ObjectBody).body : null;
  const response = new Response(body, { status: range ? 206 : 200, headers });
  if (!range && request.method === "GET") {
    const cachedResponse = response.clone();
    cachedResponse.headers.set("Cache-Control", "public, max-age=86400");
    ctx.waitUntil(caches.default.put(cacheKey, cachedResponse));
  }
  return response;
}

const worker = {
  fetch(request: Request, env: Env, ctx: ExecutionContext) { return serve({ request, env, ctx }); },
};

export default worker;

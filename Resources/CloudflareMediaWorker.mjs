export const VERSION = 1;

const ID = "[a-f0-9-]{36}";
const FILES = { "video.mp4": "video/mp4", "poster.jpg": "image/jpeg" };
const PART_BYTES = 64 * 1024 * 1024;

function cors(extra = {}) {
  return new Headers({
    "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "Range, If-None-Match, If-Range",
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, ETag",
    "Cross-Origin-Resource-Policy": "cross-origin", "X-Content-Type-Options": "nosniff", ...extra,
  });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors({ "Content-Type": "application/json", "Cache-Control": "no-store" }) });
}

async function authorized({ request, env }) {
  const expected = new TextEncoder().encode(`Bearer ${env.UPLOAD_SECRET}`);
  const provided = new TextEncoder().encode(request.headers.get("Authorization") ?? "");
  if (!env.UPLOAD_SECRET || expected.byteLength !== provided.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < expected.byteLength; index += 1) difference |= expected[index] ^ provided[index];
  return difference === 0;
}

async function serveFile({ request, env, id, name }) {
  const key = `videos/${id}/${name}`;
  const object = request.method === "HEAD"
    ? await env.MEDIA.head(key)
    : await env.MEDIA.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response(null, { status: 404, headers: cors({ "Cache-Control": "no-store" }) });
  const headers = cors({
    "Content-Type": FILES[name], "ETag": object.httpEtag, "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=31536000, immutable",
  });
  const range = "body" in object ? object.range : undefined;
  if (request.method !== "HEAD" && !("body" in object)) return new Response(null, { status: 304, headers });
  if (range && request.headers.has("Range")) {
    const offset = "offset" in range && range.offset !== undefined ? range.offset
      : "suffix" in range ? Math.max(0, object.size - range.suffix) : 0;
    const length = "length" in range && range.length !== undefined ? range.length : object.size - offset;
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("Content-Length", String(length));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("Content-Length", String(object.size));
  return new Response(request.method === "HEAD" ? null : object.body, { status: 200, headers });
}

async function write({ request, env, url, id, name }) {
  const key = `videos/${id}/${name}`;
  const uploadId = url.searchParams.get("uploadId");
  if (request.method === "PUT" && name === "poster.jpg") {
    const length = Number(request.headers.get("Content-Length"));
    if (!Number.isSafeInteger(length) || length < 4 || length > 1024 * 1024) return json({ error: "Invalid poster." }, 400);
    await env.MEDIA.put(key, request.body, { httpMetadata: { contentType: FILES[name] } });
    return json({ saved: true });
  }
  if (name !== "video.mp4") return json({ error: "Not found." }, 404);
  if (request.method === "POST" && url.searchParams.has("uploads")) {
    const upload = await env.MEDIA.createMultipartUpload(key, { httpMetadata: { contentType: FILES[name] } });
    return json({ uploadId: upload.uploadId });
  }
  if (!uploadId) return json({ error: "Missing upload." }, 400);
  const upload = env.MEDIA.resumeMultipartUpload(key, uploadId);
  if (request.method === "PUT") {
    const part = Number(url.searchParams.get("part"));
    const length = Number(request.headers.get("Content-Length"));
    if (!Number.isSafeInteger(part) || part < 1 || part > 10_000) return json({ error: "Invalid part." }, 400);
    if (!Number.isSafeInteger(length) || length < 1 || length > PART_BYTES) return json({ error: "Invalid part size." }, 400);
    const uploaded = await upload.uploadPart(part, request.body);
    return json({ part: uploaded.partNumber, etag: uploaded.etag });
  }
  if (request.method === "POST") {
    const body = await request.json().catch(() => null);
    const parts = Array.isArray(body?.parts) ? body.parts : [];
    if (!parts.length || parts.some((part) => !Number.isSafeInteger(part?.part) || typeof part?.etag !== "string")) {
      return json({ error: "Invalid parts." }, 400);
    }
    const object = await upload.complete(parts.map((part) => ({ partNumber: part.part, etag: part.etag })));
    return json({ bytes: object.size });
  }
  return json({ error: "Not found." }, 404);
}

async function remove({ env, id }) {
  const listed = await env.MEDIA.list({ prefix: `videos/${id}/` });
  if (listed.objects.length) await env.MEDIA.delete(listed.objects.map((object) => object.key));
  return json({ deleted: true });
}

export async function serve({ request, env }) {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors() });
  if (url.pathname === "/health" && request.method === "GET") {
    return json({ blitzrecorder: true, version: VERSION, upload: await authorized({ request, env }) });
  }
  const read = new RegExp(`^/v/(${ID})/(video\\.mp4|poster\\.jpg)$`).exec(url.pathname);
  if (read && ["GET", "HEAD"].includes(request.method)) return serveFile({ request, env, id: read[1], name: read[2] });
  const owner = new RegExp(`^/u/(${ID})(?:/(video\\.mp4|poster\\.jpg))?$`).exec(url.pathname);
  if (!owner) return json({ error: "Not found." }, 404);
  if (!await authorized({ request, env })) return json({ error: "Not authorized." }, 401);
  try {
    if (!owner[2]) return request.method === "DELETE" ? remove({ env, id: owner[1] }) : json({ error: "Not found." }, 404);
    return await write({ request, env, url, id: owner[1], name: owner[2] });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Storage request failed." }, 502);
  }
}

export default {
  fetch(request, env) { return serve({ request, env }); },
};

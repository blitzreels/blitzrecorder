import { createServer } from "node:http";
import { Readable } from "node:stream";
import { HeadObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { r2 } from "../lib/hosting/r2";
import { required } from "../lib/hosting/model";

async function main() {
  const site = new URL(required("NEXT_PUBLIC_SITE_URL"));
  const media = new URL(required("HOSTING_MEDIA_ORIGIN"));
  if (process.env.NODE_ENV === "production" || site.hostname !== "localhost" || media.hostname !== "localhost") {
    throw new Error("This delivery adapter is for local validation only.");
  }
  const workerPath = new URL("../hosting-worker/index.ts", import.meta.url).href;
  const worker = await import(workerPath);
  const saved = new Map<string, { body: ArrayBuffer; headers: Headers; status: number; expires: number }>();
  const cache = {
    async match(request: Request) {
      const entry = saved.get(request.url);
      if (!entry || entry.expires < Date.now()) return undefined;
      const headers = new Headers(entry.headers);
      const range = worker.requestedRange({ header: request.headers.get("Range"), size: entry.body.byteLength });
      if (range) {
        headers.set("Content-Range", `bytes ${range.offset}-${range.offset + range.length - 1}/${entry.body.byteLength}`);
        headers.set("Content-Length", String(range.length));
        return new Response(entry.body.slice(range.offset, range.offset + range.length), { status: 206, headers });
      }
      return new Response(entry.body.slice(0), { status: entry.status, headers });
    },
    async put(request: Request, response: Response) {
      if (saved.size > 200) saved.delete(saved.keys().next().value!);
      const age = Number(/max-age=(\d+)/.exec(response.headers.get("Cache-Control") ?? "")?.[1] ?? 0);
      saved.set(request.url, { body: await response.arrayBuffer(), headers: new Headers(response.headers), status: response.status, expires: Date.now() + age * 1000 });
    },
  };
  Object.defineProperty(globalThis, "caches", { value: { default: cache }, configurable: true });
  const env = {
    SITE_ORIGIN: site.origin, DELIVERY_SECRET: required("HOSTING_DELIVERY_SECRET"),
    MEDIA: {
      async head(key: string) {
        try {
          const object = await r2().send(new HeadObjectCommand({ Bucket: required("HOSTING_R2_BUCKET"), Key: key }));
          return { httpEtag: object.ETag, size: object.ContentLength };
        } catch (error) {
          if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return null;
          throw error;
        }
      },
      async get(key: string, options: { range: { offset: number; length: number } } | undefined) {
        try {
          const range = options?.range;
          const object = await r2().send(new GetObjectCommand({
            Bucket: required("HOSTING_R2_BUCKET"), Key: key,
            Range: range ? `bytes=${range.offset}-${range.offset + range.length - 1}` : undefined,
          }));
          return { httpEtag: object.ETag, size: object.ContentLength, body: Readable.toWeb(object.Body as Readable) };
        } catch (error) {
          if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return null;
          throw error;
        }
      },
    },
  };
  const server = createServer(async (incoming, outgoing) => {
    try {
      const headers = new Headers();
      for (const [name, value] of Object.entries(incoming.headers)) if (value) headers.set(name, Array.isArray(value) ? value.join(",") : value);
      const request = new Request(new URL(incoming.url ?? "/", media), { method: incoming.method, headers });
      const response: Response = await worker.serve({ request, env, ctx: { waitUntil: (task: Promise<unknown>) => { void task.catch(() => undefined); } } });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) Readable.fromWeb(response.body as import("node:stream/web").ReadableStream).pipe(outgoing);
      else outgoing.end();
    } catch {
      if (!outgoing.headersSent) outgoing.writeHead(503);
      outgoing.end();
    }
  });
  server.listen(Number(media.port), "127.0.0.1", () => console.log(`Local delivery adapter on ${media.origin}`));
}

main().catch((error) => { console.error(error instanceof Error ? error.message : "Delivery failed."); process.exitCode = 1; });

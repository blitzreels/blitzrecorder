import {
  authenticate, authenticateDelivery, beginUpload, finishUpload, listAssets,
  preparePart, resumeUpload, revokeAsset, sharedAsset, updateDetails,
} from "@/lib/hosting/service";
import { DELIVERY_TTL_SECONDS, HostingError } from "@/lib/hosting/model";
import { accountState, billingURL, connectAccount, disconnectAccount, verifyIdentity } from "@/lib/hosting/account";
import { DETAILS_MAX_BYTES } from "@/lib/hosting/details";
import { hostingPlan } from "@/lib/hosting/plan";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

async function readBody({ request, limit }: { request: Request; limit: number }): Promise<unknown> {
  if (Number(request.headers.get("content-length")) > limit) throw new HostingError({ status: 413, message: "Request is too large." });
  const reader = request.body?.getReader();
  if (!reader) throw new HostingError({ status: 400, message: "Missing request body." });
  let text = "";
  let length = 0;
  const decoder = new TextDecoder();
  for (;;) {
    const next = await reader.read();
    if (next.done) break;
    length += next.value.length;
    if (length > limit) { await reader.cancel(); throw new HostingError({ status: 413, message: "Request is too large." }); }
    text += decoder.decode(next.value, { stream: true });
  }
  try { return JSON.parse(text + decoder.decode()); }
  catch { throw new HostingError({ status: 400, message: "Invalid request body." }); }
}

async function handle(request: Request) {
  try {
    const path = new URL(request.url).pathname.replace(/^\/api\/hosting\//, "").split("/");
    const [resource, id, action] = path;
    let result: unknown;
    if (request.method === "GET" && resource === "plan" && path.length === 1) {
      result = hostingPlan();
    } else if (request.method === "POST" && resource === "connect" && path.length === 1) {
      result = await connectAccount(await verifyIdentity(request));
    } else if (request.method === "GET" && resource === "delivery" && path.length === 2) {
      authenticateDelivery(request);
      const asset = await sharedAsset(id);
      if (!asset) throw new HostingError({ status: 404, message: "Video unavailable." });
      result = { prefix: asset.stream_prefix, files: asset.files, ttl: DELIVERY_TTL_SECONDS };
    } else {
      const account = await authenticate(request);
      if (resource === "account" && path.length === 1 && request.method === "GET") result = accountState(account);
      else if (resource === "billing" && path.length === 1 && request.method === "POST") result = await billingURL(account);
      else if (resource === "disconnect" && path.length === 1 && request.method === "POST") result = await disconnectAccount(request);
      else if (resource !== "assets") throw new HostingError({ status: 404, message: "Not found." });
      else if (request.method === "GET" && path.length === 1) result = await listAssets(account);
      else if (request.method === "POST" && path.length === 1) result = await beginUpload({ account, body: await readBody({ request, limit: 16_384 }) });
      else if (request.method === "GET" && path.length === 2) result = await resumeUpload({ account, id });
      else if (request.method === "DELETE" && path.length === 2) result = await revokeAsset({ account, id });
      else if (request.method === "POST" && path.length === 3 && action === "complete") result = await finishUpload({ account, id });
      else if (request.method === "POST" && path.length === 3 && action === "details") {
        result = await updateDetails({ account, id, body: await readBody({ request, limit: DETAILS_MAX_BYTES }) });
      }
      else if (request.method === "POST" && path.length === 3 && action === "parts") {
        const body = await readBody({ request, limit: 16_384 }) as { number: number };
        result = await preparePart({ account, id, number: body?.number });
      } else throw new HostingError({ status: 404, message: "Not found." });
    }
    return Response.json(result, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    const known = error instanceof HostingError;
    if (!known) console.error("Hosting request failed", error instanceof Error
      ? { name: error.name, message: error.message.replace(/(?:sk|rk|whsec)_[A-Za-z0-9_]+/g, "[redacted]") }
      : "Unknown error");
    return Response.json({ error: known ? error.message : "Video hosting is temporarily unavailable. Please retry." }, {
      status: known ? error.status : 503, headers: { "Cache-Control": "no-store" },
    });
  }
}

export const GET = handle;
export const POST = handle;
export const DELETE = handle;

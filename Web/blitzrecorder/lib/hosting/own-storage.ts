import { HostingError } from "./model";

/** Size of a file in the owner's media worker, or null when it is missing. */
export async function ownStorageBytes({ origin, id, path }: { origin: string; id: string; path: string }): Promise<number | null> {
  let response: Response;
  try {
    response = await fetch(`${origin}/v/${id}/${path}`, { method: "HEAD", redirect: "manual", signal: AbortSignal.timeout(10_000) });
  } catch {
    throw new HostingError({ status: 502, message: "Your Cloudflare storage didn’t respond. Check your connection and try again." });
  }
  if (response.status === 404) return null;
  const bytes = Number(response.headers.get("content-length"));
  if (!response.ok || !Number.isSafeInteger(bytes)) {
    throw new HostingError({ status: 502, message: "Your Cloudflare storage didn’t respond. Check your connection and try again." });
  }
  return bytes;
}

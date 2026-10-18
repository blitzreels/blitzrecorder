/** The visitor's IP as Vercel reports it, used only for rate limits. "unknown" off Vercel. */
export function clientNetwork(request: Request): string {
  return request.headers.get("x-vercel-forwarded-for")?.split(",")[0]?.trim() || "unknown";
}

import { NextResponse } from "next/server";
import { z } from "zod";
import { HostingError } from "@/lib/hosting/model";
import { verifySignInCode } from "@/lib/hosting/sign-in";
import { SESSION_COOKIE, SESSION_COOKIE_OPTIONS } from "@/lib/hosting/web-session";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const FORBIDDEN = "This request was blocked for your security. Reload the page and try again.";
const verifyInput = z.object({ challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/), code: z.string().regex(/^\d{6}$/) });

function reply({ body, status = 200 }: { body: unknown; status?: number }) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

/** Cookie-bearing writes must come from this site; SameSite=Lax alone still allows same-site subdomains. */
function sameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
  if (!origin || !host) return false;
  try { return new URL(origin).host === host; } catch { return false; }
}

export async function POST(request: Request) {
  if (!sameOrigin(request)) return reply({ body: { error: FORBIDDEN }, status: 403 });
  if (Number(request.headers.get("content-length")) > 2048) return reply({ body: { error: "Request is too large." }, status: 413 });
  const input = verifyInput.safeParse(await request.json().catch(() => null));
  if (!input.success) return reply({ body: { error: "This code is invalid or expired. Request a new code and try again." }, status: 400 });
  try {
    const { token, email } = await verifySignInCode(input.data);
    const response = reply({ body: { email } });
    response.cookies.set(SESSION_COOKIE, token, SESSION_COOKIE_OPTIONS);
    return response;
  } catch (error) {
    if (error instanceof HostingError) return reply({ body: { error: error.message }, status: error.status });
    console.error("Hosting web sign-in failed", error instanceof Error ? error.name : "Unknown error");
    return reply({ body: { error: "Sign-in is temporarily unavailable. Please retry." }, status: 503 });
  }
}
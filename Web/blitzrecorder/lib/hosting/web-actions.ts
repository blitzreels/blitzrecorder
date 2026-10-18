"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { z } from "zod";
import { hostingPool } from "@/lib/hosting/db";
import { billingURL, signOutEverywhere } from "@/lib/hosting/account";
import { HostingError, tokenHash } from "@/lib/hosting/model";
import { planPath } from "@/lib/hosting/paths";
import { setCancelAtPeriodEnd } from "@/lib/hosting/subscription";
import {
  SESSION_COOKIE, SESSION_COOKIE_OPTIONS, sessionToken, setVideoListing, stopSharingVideo, viewerAccount,
} from "@/lib/hosting/web-session";

export type HostingActionResult = { ok: true } | { ok: false; error: string };

const SESSION_EXPIRED = "Your session expired. Sign in again to manage your videos.";
const UNAVAILABLE = "Something went wrong on our side. Try again in a moment.";
const scopeInput = z.enum(["device", "everywhere"]);
const slugInput = z.string().regex(/^[A-Za-z0-9_-]{24}$/);
const listingInput = z.object({ slug: slugInput, listed: z.boolean() });

async function clearSession() {
  (await cookies()).set(SESSION_COOKIE, "", { ...SESSION_COOKIE_OPTIONS, maxAge: 0 });
}

export async function signOut(scope: unknown): Promise<HostingActionResult> {
  const input = scopeInput.safeParse(scope);
  if (!input.success) return { ok: false, error: UNAVAILABLE };
  const token = await sessionToken();
  if (!token) { await clearSession(); return { ok: true }; }
  try {
    if (input.data === "everywhere") {
      const account = await viewerAccount();
      if (!account) { await clearSession(); return { ok: true }; }
      await signOutEverywhere(account);
    } else {
      await hostingPool().query("DELETE FROM hosting_connections WHERE token_hash=$1", [tokenHash(token)]);
    }
  } catch (error) {
    console.error("Hosting web sign-out failed", error instanceof Error ? error.name : "Unknown error");
    if (input.data === "everywhere") return { ok: false, error: "Couldn’t sign out your other devices. Try again." };
  }
  await clearSession();
  return { ok: true };
}

export async function setListing(input: unknown): Promise<HostingActionResult> {
  const parsed = listingInput.safeParse(input);
  if (!parsed.success) return { ok: false, error: "This video can’t be found." };
  try {
    const account = await viewerAccount();
    if (!account) return { ok: false, error: SESSION_EXPIRED };
    if (!await setVideoListing({ account, slug: parsed.data.slug, listed: parsed.data.listed })) {
      return { ok: false, error: "This video can’t be listed right now. Reload and try again." };
    }
    return { ok: true };
  } catch (error) {
    console.error("Hosting listing change failed", error instanceof Error ? error.name : "Unknown error");
    return { ok: false, error: UNAVAILABLE };
  }
}

export async function stopSharing(slug: unknown): Promise<HostingActionResult> {
  const input = slugInput.safeParse(slug);
  if (!input.success) return { ok: false, error: "This video can’t be found." };
  try {
    const account = await viewerAccount();
    if (!account) return { ok: false, error: SESSION_EXPIRED };
    if (!await stopSharingVideo({ account, slug: input.data })) {
      return { ok: false, error: "This video is no longer shared. Reload to see your current videos." };
    }
    return { ok: true };
  } catch (error) {
    console.error("Hosting stop sharing failed", error instanceof Error ? error.name : "Unknown error");
    return { ok: false, error: UNAVAILABLE };
  }
}

/** Stripe's billing portal for subscribers, checkout for everyone else. */
export async function openBilling(): Promise<{ ok: true; url: string } | { ok: false; error: string }> {
  const account = await viewerAccount();
  if (!account) return { ok: false, error: SESSION_EXPIRED };
  try {
    return { ok: true, url: (await billingURL({ account, returnPath: planPath })).url };
  } catch (error) {
    if (error instanceof HostingError) return { ok: false, error: error.message };
    console.error("Hosting billing link failed", error instanceof Error ? error.name : "Unknown error");
    return { ok: false, error: UNAVAILABLE };
  }
}

/** Cancel at period end, or resume a subscription that is set to cancel. */
export async function setSubscriptionCanceling(cancel: unknown): Promise<HostingActionResult> {
  const input = z.boolean().safeParse(cancel);
  if (!input.success) return { ok: false, error: UNAVAILABLE };
  const account = await viewerAccount();
  if (!account) return { ok: false, error: SESSION_EXPIRED };
  try {
    await setCancelAtPeriodEnd({ account, cancel: input.data });
    revalidatePath(planPath);
    return { ok: true };
  } catch (error) {
    if (error instanceof HostingError) return { ok: false, error: error.message };
    console.error("Hosting subscription change failed", error instanceof Error ? error.name : "Unknown error");
    return { ok: false, error: UNAVAILABLE };
  }
}

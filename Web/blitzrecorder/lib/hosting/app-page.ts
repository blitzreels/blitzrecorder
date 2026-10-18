import { redirect } from "next/navigation";
import { cache } from "react";
import { accountOverview, type AccountOverview } from "./account";
import type { HostingAccount } from "./model";
import { signInFor } from "./paths";
import { viewerAccount } from "./web-session";

export type AppAccount = { account: HostingAccount; overview: AccountOverview };

/**
 * The signed-in account and the numbers the sidebar shows, loaded once per request and shared by the
 * dashboard layout and its pages. Null when hosting is off or nobody is signed in; the layout handles both.
 */
export const appAccount = cache(async (): Promise<AppAccount | null> => {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return null;
  const account = await viewerAccount();
  return account ? { account, overview: await accountOverview(account) } : null;
});

/**
 * For dashboard pages. Null when hosting is off (the layout shows its status screen instead).
 * Signed out, it redirects to sign-in with `path` as the way back.
 */
export async function requireAppAccount(path: string): Promise<AppAccount | null> {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return null;
  const app = await appAccount();
  if (!app) redirect(signInFor(path));
  return app;
}

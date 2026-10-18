import Link from "next/link";
import type { ReactNode } from "react";
import { AppShell, appLinks } from "@/components/hosting/app-shell";
import { ShellSignOut } from "@/components/hosting/shell-sign-out";
import { StatusScreen } from "@/components/hosting/status-screen";
import { Button } from "@/components/ui/button";
import { appAccount } from "@/lib/hosting/app-page";

/**
 * Signed-in dashboard. The shell stays mounted while you move between pages; only the content swaps.
 * Signed out, each page redirects to sign-in with its own path, so people land back where they were.
 */
export default async function DashboardLayout({ children }: { children: ReactNode }) {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") {
    return <StatusScreen mark="Soon" title="Video sharing isn’t available yet" footer={null}
      actions={<Button size="lg" variant="outline" render={<Link href="/" />}>Go home</Button>}>
      Your recordings stay on your Mac. Sharing links will open here once hosting launches.
    </StatusScreen>;
  }
  const app = await appAccount();
  if (!app) return children;
  return <AppShell links={appLinks} account={app.overview} signOut={<ShellSignOut />}>{children}</AppShell>;
}

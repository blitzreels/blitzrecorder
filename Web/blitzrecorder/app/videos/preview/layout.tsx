import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { AppShell } from "@/components/hosting/app-shell";
import { previewLinks, previewOverview } from "./links";
import { PreviewSignOut } from "./sign-out";

/** Local fixture of the dashboard with fake data. Production 404s. */
export default function PreviewLayout({ children }: { children: ReactNode }) {
  if (process.env.NODE_ENV === "production") notFound();
  return <AppShell links={previewLinks} account={previewOverview} signOut={<PreviewSignOut />}>{children}</AppShell>;
}

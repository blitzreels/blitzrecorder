import type { Metadata } from "next";
import { AccountPanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import { requireAppAccount } from "@/lib/hosting/app-page";
import { accountPath } from "@/lib/hosting/paths";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Account — BlitzRecorder", robots: { index: false, follow: false } };

export default async function AccountPage() {
  const app = await requireAppAccount(accountPath);
  if (!app) return null;
  return <>
    <PageHeader title="Account" description="Your sign-in and the devices connected to it." actions={null} />
    <AccountPanel overview={app.overview} mode="live" />
  </>;
}

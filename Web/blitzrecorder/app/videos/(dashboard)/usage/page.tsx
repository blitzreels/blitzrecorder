import type { Metadata } from "next";
import { UsagePanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import { requireAppAccount } from "@/lib/hosting/app-page";
import { usagePath } from "@/lib/hosting/paths";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Usage — BlitzRecorder", robots: { index: false, follow: false } };

export default async function UsagePage() {
  const app = await requireAppAccount(usagePath);
  if (!app) return null;
  return <>
    <PageHeader title="Usage" description="Storage and uploads on BlitzRecorder hosting." actions={null} />
    <UsagePanel overview={app.overview} />
  </>;
}

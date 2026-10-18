import type { Metadata } from "next";
import { PlanPanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import { requireAppAccount } from "@/lib/hosting/app-page";
import { planPath } from "@/lib/hosting/paths";
import { subscriptionView } from "@/lib/hosting/subscription";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Plan & billing — BlitzRecorder", robots: { index: false, follow: false } };

export default async function PlanPage() {
  const app = await requireAppAccount(planPath);
  if (!app) return null;
  return <>
    <PageHeader title="Plan & billing" description="Your hosting plan, card, and invoices." actions={null} />
    <PlanPanel subscription={await subscriptionView(app.account)} mode="live" />
  </>;
}

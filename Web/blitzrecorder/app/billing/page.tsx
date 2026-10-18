import Link from "next/link";
import { StatusScreen } from "@/components/hosting/status-screen";
import { Button } from "@/components/ui/button";
import { planPath } from "@/lib/hosting/paths";

export const metadata = { title: "Video hosting — BlitzRecorder", robots: { index: false, follow: false } };

/** Where Stripe sends people who started checkout from the Mac app. */
export default async function HostingComplete({ searchParams }: { searchParams: Promise<{ cancelled?: string }> }) {
  const cancelled = (await searchParams).cancelled === "1";
  return cancelled
    ? <StatusScreen mark="Later" title="No charge was made" footer={null}
      actions={<Button size="lg" variant="outline" render={<Link href="/" />}>Back to BlitzRecorder</Button>}>
      Your video is still on your Mac and nothing was uploaded. Subscribe from Share in the app whenever you&apos;re ready.
    </StatusScreen>
    : <StatusScreen mark="Paid" title="You’re subscribed" footer="Your exports stay free with or without a plan."
      actions={<Button size="lg" variant="outline" render={<Link href={planPath} />}>See your plan</Button>}>
      Go back to Share in BlitzRecorder. Your plan turns on by itself as soon as Stripe confirms the payment.
    </StatusScreen>;
}

import { PlanPanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import type { SubscriptionState, SubscriptionView } from "@/lib/hosting/subscription";

const STATES: SubscriptionState[] = ["none", "active", "canceling", "past_due", "ended", "unavailable"];

const invoices: SubscriptionView["invoices"] = [
  { id: "in_3", number: "BR-0003", date: "2026-10-14T00:00:00.000Z", amount: 1080, currency: "eur", status: "paid", url: "#" },
  { id: "in_2", number: "BR-0002", date: "2026-09-14T00:00:00.000Z", amount: 1080, currency: "eur", status: "paid", url: "#" },
  { id: "in_1", number: "BR-0001", date: "2026-08-14T00:00:00.000Z", amount: 1080, currency: "eur", status: "paid", url: "#" },
];

/** Every plan state with fake Stripe data: `?state=none|active|canceling|past_due|ended`. */
export default async function PlanPreview({ searchParams }: { searchParams: Promise<{ state?: string }> }) {
  const asked = (await searchParams).state;
  const state = STATES.find((value) => value === asked) ?? "active";
  const subscription: SubscriptionView = state === "none" || state === "unavailable"
    ? { state, periodEnd: null, card: null, invoices: [] }
    : { state, periodEnd: state === "ended" ? "2026-10-14T00:00:00.000Z" : "2026-11-14T00:00:00.000Z",
      card: { brand: "visa", last4: "4242", expMonth: 8, expYear: 2028 }, invoices };
  return <>
    <PageHeader title="Plan & billing" description="Your hosting plan, card, and invoices." actions={null} />
    <PlanPanel subscription={subscription} mode="preview" />
  </>;
}

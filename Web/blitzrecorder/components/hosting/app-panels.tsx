"use client";

import { useActionState, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { SignOutButton } from "@/components/hosting/sign-out-button";
import { Button, buttonVariants } from "@/components/ui/button";
import type { AccountOverview } from "@/lib/hosting/account";
import { HOSTING_PLAN } from "@/lib/hosting/plan";
import type { SubscriptionView } from "@/lib/hosting/subscription";
import { openBilling, setSubscriptionCanceling, type HostingActionResult } from "@/lib/hosting/web-actions";
import { formatBytes, formatMinutes } from "@/lib/format";
import { cn } from "@/lib/utils";

const money = ({ cents, currency }: { cents: number; currency: string }) =>
  new Intl.NumberFormat("en", { style: "currency", currency, maximumFractionDigits: cents % 100 === 0 ? 0 : 2 }).format(cents / 100);
const price = money({ cents: HOSTING_PLAN.amount, currency: HOSTING_PLAN.currency });
const longDate = (iso: string) => new Date(iso).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" });
const shortDate = (iso: string) => new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });

/** Preview pages render every state without touching Stripe. */
export type PanelMode = "live" | "preview";

export function UsagePanel({ overview }: { overview: AccountOverview }) {
  return <div className="flex flex-col gap-8">
    <Group title="This plan">
      <Meter label="Storage" used={overview.storedBytes} limit={overview.storageLimit}
        caption={`${formatBytes(overview.storedBytes)} of ${formatBytes(overview.storageLimit)}`} />
      <Meter label={`Uploads in the last ${HOSTING_PLAN.uploadWindowDays} days`} used={overview.uploadedSeconds}
        limit={HOSTING_PLAN.uploadSeconds}
        caption={`${formatMinutes(overview.uploadedSeconds)} of ${formatMinutes(HOSTING_PLAN.uploadSeconds)}`} />
    </Group>
    <p className="text-[13px] leading-6 text-faint">
      Uploads count the length of each video you share, over a rolling {HOSTING_PLAN.uploadWindowDays} days. Videos shared
      through your own Cloudflare account don&apos;t count toward either limit. Streams play in up to {HOSTING_PLAN.maximumResolution}p.
    </p>
  </div>;
}

export function PlanPanel({ subscription, mode }: { subscription: SubscriptionView; mode: PanelMode }) {
  const end = subscription.periodEnd ? longDate(subscription.periodEnd) : null;
  const summary: Record<SubscriptionView["state"], { status: string; detail: string }> = {
    none: {
      status: "Free plan",
      detail: "Share links through your own Cloudflare account at no cost from us. Hosting adds 50 GB on our servers, "
        + `${formatMinutes(HOSTING_PLAN.uploadSeconds)} of uploads every ${HOSTING_PLAN.uploadWindowDays} days, and ${HOSTING_PLAN.maximumResolution}p streaming.`,
    },
    active: { status: `Hosting · ${price} a month`, detail: end ? `Renews on ${end}.` : "Renews every month." },
    canceling: {
      status: "Hosting · canceled",
      detail: `Your links keep working until ${end ?? "the end of this period"}. Hosted videos are deleted `
        + `${HOSTING_PLAN.retentionDaysAfterExpiry} days after that unless you resume.`,
    },
    past_due: {
      status: "Hosting · payment failed",
      detail: "Your last payment didn't go through. Update your card to keep your links working.",
    },
    unavailable: {
      status: "Billing details unavailable",
      detail: "We couldn't reach Stripe just now. Your plan hasn't changed. Open billing to manage it, or try again in a minute.",
    },
    ended: {
      status: "Hosting ended",
      detail: `${end ? `It ended on ${end}. ` : ""}Videos are kept for ${HOSTING_PLAN.retentionDaysAfterExpiry} days after a plan ends. `
        + "Subscribe again to bring your links back.",
    },
  };
  const current = summary[subscription.state];

  return <div className="flex flex-col gap-8">
    <Group title="Current plan">
      <div className="flex flex-col gap-5 px-5 py-5 sm:flex-row sm:items-start sm:justify-between sm:px-6">
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-[17px] font-semibold tracking-[-0.01em]">
            <span aria-hidden className={cn("size-2 rounded-full", {
              none: "bg-white/30", active: "bg-primary", canceling: "bg-warning", past_due: "bg-record", ended: "bg-white/30", unavailable: "bg-warning",
            }[subscription.state])} />
            {current.status}
          </p>
          <p className="mt-2 max-w-[52ch] text-[14px] leading-6 text-pretty text-muted-foreground">{current.detail}</p>
        </div>
        <div className="flex shrink-0 flex-wrap gap-2 sm:justify-end">
          <PlanActions state={subscription.state} mode={mode} />
        </div>
      </div>
    </Group>

    {subscription.state !== "none" && subscription.state !== "unavailable" ? <Group title="Payment method">
      <Row
        label={subscription.card ? `${brand(subscription.card.brand)} ending in ${subscription.card.last4}` : "No card on file"}
        detail={subscription.card
          ? `Expires ${String(subscription.card.expMonth).padStart(2, "0")}/${String(subscription.card.expYear).slice(-2)}`
          : "Add a card when you subscribe."}
        action={<BillingButton label="Update card" variant="outline" mode={mode} />}
      />
    </Group> : null}

    {subscription.invoices.length > 0 ? <Group title="Invoices">
      <ul>
        {subscription.invoices.map((invoice) => <li key={invoice.id}
          className="grid grid-cols-[minmax(0,1fr)_auto_auto] items-center gap-4 px-5 py-3.5 text-[14px] sm:grid-cols-[9rem_minmax(0,1fr)_auto_auto] sm:px-6">
          <span className="tabular-nums">{shortDate(invoice.date)}</span>
          <span className="hidden truncate text-faint sm:block">{invoice.number ?? "Invoice"}</span>
          <span className="tabular-nums">{money({ cents: invoice.amount, currency: invoice.currency })}
            <span className="ml-2 text-faint">{invoice.status === "paid" ? "Paid" : invoice.status === "open" ? "Due" : "Void"}</span>
          </span>
          {invoice.url
            ? <a href={invoice.url} target="_blank" rel="noopener" className="text-[13px] font-medium text-muted-foreground underline decoration-white/20 underline-offset-4 hover:text-foreground">View</a>
            : <span />}
        </li>)}
      </ul>
    </Group> : null}

    <p className="text-[13px] leading-6 text-faint">
      Billing runs on Stripe. Canceling stops the next charge and keeps your links live until the paid period ends.
      Your Mac app and local exports stay free whatever your plan.
    </p>
  </div>;
}

function PlanActions({ state, mode }: { state: SubscriptionView["state"]; mode: PanelMode }) {
  if (state === "none") return <BillingButton label={`Subscribe for ${price} a month`} variant="default" mode={mode} />;
  if (state === "ended") return <BillingButton label={`Subscribe again for ${price} a month`} variant="default" mode={mode} />;
  if (state === "past_due") return <BillingButton label="Update card" variant="default" mode={mode} />;
  if (state === "unavailable") return <BillingButton label="Open billing" variant="outline" mode={mode} />;
  if (state === "canceling") return <CancelToggle cancel={false} mode={mode} />;
  return <CancelToggle cancel mode={mode} />;
}

function BillingButton({ label, variant, mode }: { label: string; variant: "default" | "outline"; mode: PanelMode }) {
  const [state, action, pending] = useActionState(async () => {
    const result = await openBilling();
    if (result.ok) window.location.assign(result.url);
    return result;
  }, null);
  return <form action={action} className="flex flex-col items-start gap-2 sm:items-end">
    <Button type="submit" size="sm" variant={variant} disabled={pending || mode === "preview"}>{pending ? "Opening Stripe…" : label}</Button>
    {state && !state.ok ? <p role="alert" className="max-w-64 text-[13px] text-warning">{state.error}</p> : null}
  </form>;
}

/** Cancel asks once more in place; resume is one click. */
function CancelToggle({ cancel, mode }: { cancel: boolean; mode: PanelMode }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [state, action, pending] = useActionState<HostingActionResult | null>(async () => {
    const result = await setSubscriptionCanceling(cancel);
    if (result.ok) { setConfirming(false); router.refresh(); }
    return result;
  }, null);
  const failed = state && !state.ok ? <p role="alert" className="max-w-64 text-[13px] text-warning">{state.error}</p> : null;
  if (!cancel) {
    return <form action={action} className="flex flex-col items-start gap-2 sm:items-end">
      <Button type="submit" size="sm" disabled={pending || mode === "preview"}>{pending ? "Resuming…" : "Resume subscription"}</Button>
      {failed}
    </form>;
  }
  if (!confirming) {
    return <div className="flex flex-wrap gap-2">
      <BillingButton label="Manage in Stripe" variant="outline" mode={mode} />
      <Button size="sm" variant="ghost" onClick={() => setConfirming(true)}>Cancel subscription</Button>
    </div>;
  }
  return <form action={action} className="flex flex-col items-start gap-2 sm:items-end">
    <p className="text-[13px] text-muted-foreground">No more charges. Links stay live until the period ends.</p>
    <div className="flex gap-2">
      <Button type="button" size="sm" variant="outline" onClick={() => setConfirming(false)}>Keep plan</Button>
      <Button type="submit" size="sm" variant="destructive" disabled={pending || mode === "preview"}>
        {pending ? "Canceling…" : "Confirm cancel"}
      </Button>
    </div>
    {failed}
  </form>;
}

export function AccountPanel({ overview, mode }: { overview: AccountOverview; mode: PanelMode }) {
  return <div className="flex flex-col gap-8">
    <Group title="Profile">
      <Row label="Email" detail={overview.email ?? "No email on this account"} action={null} />
    </Group>
    <Group title="Sessions">
      <Row
        label="This browser"
        detail="Sign out here. Your Mac app stays signed in."
        action={mode === "preview" ? <Button size="sm" variant="outline" disabled>Sign out</Button>
          : <SignOutButton className={cn(buttonVariants({ variant: "outline", size: "sm" }))} />}
      />
      <Row
        label="All devices"
        detail={overview.sessions === 1
          ? "You're only signed in here."
          : `Signed in on ${overview.sessions} devices, Macs included. Signing out everywhere ends all of them.`}
        action={overview.sessions > 1
          ? mode === "preview" ? <Button size="sm" variant="outline" disabled>Sign out everywhere</Button>
            : <SignOutButton scope="everywhere" className={cn(buttonVariants({ variant: "outline", size: "sm" }))}>Sign out everywhere</SignOutButton>
          : null}
      />
    </Group>
    <Group title="Delete account">
      <Row label="Remove your account and hosted videos"
        detail="Cancel any plan first, then email us from this address and we'll delete everything."
        action={<a href="mailto:support@blitzreels.com?subject=Delete%20my%20BlitzRecorder%20account"
          className={cn(buttonVariants({ variant: "outline", size: "sm" }))}>Email support</a>} />
    </Group>
  </div>;
}

function brand(name: string) {
  const names: Record<string, string> = { amex: "Amex", mastercard: "Mastercard", visa: "Visa", discover: "Discover", jcb: "JCB", unionpay: "UnionPay", cartes_bancaires: "Cartes Bancaires", diners: "Diners", link: "Link" };
  return names[name] ?? "Card";
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return <section>
    <h2 className="mb-3 text-[13px] font-medium text-white/60">{title}</h2>
    <div className="product-surface divide-y divide-white/[0.06] overflow-hidden rounded-[14px]">{children}</div>
  </section>;
}

function Row({ label, detail, action }: { label: string; detail: string; action: ReactNode }) {
  return <div className="flex flex-col gap-4 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
    <div className="min-w-0">
      <p className="text-[15px] font-medium">{label}</p>
      <p className="mt-1 text-[14px] leading-6 text-pretty text-muted-foreground">{detail}</p>
    </div>
    {action ? <div className="shrink-0">{action}</div> : null}
  </div>;
}

function Meter({ label, used, limit, caption }: { label: string; used: number; limit: number; caption: string }) {
  const share = limit > 0 ? Math.min(1, used / limit) : 0;
  return <div className="px-5 py-5 sm:px-6">
    <div className="flex items-baseline justify-between gap-4">
      <p className="text-[15px] font-medium">{label}</p>
      <p className="text-[14px] text-muted-foreground tabular-nums">{caption}</p>
    </div>
    <div role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={limit} aria-valuenow={used} aria-valuetext={caption}
      className="mt-3 h-1.5 overflow-hidden rounded-full bg-white/[0.08]">
      <div className={cn("h-full rounded-full transition-[width] duration-300", share >= 0.9 ? "bg-warning" : "bg-primary")}
        style={{ width: `${Math.max(share * 100, used > 0 ? 1 : 0)}%` }} />
    </div>
  </div>;
}

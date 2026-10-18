import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";
import { ArrowUpRight } from "lucide-react";
import { AppNav, SideLink } from "@/components/hosting/app-nav";
import { assets } from "@/lib/assets";
import { formatBytes } from "@/lib/format";
import { accountPath, planPath, usagePath, videosPath } from "@/lib/hosting/paths";
import { cn } from "@/lib/utils";

export type AppPage = "videos" | "usage" | "plan" | "account";
export type AppLinks = Record<AppPage, string>;

export const appLinks: AppLinks = { videos: videosPath, usage: usagePath, plan: planPath, account: accountPath };

export type ShellAccount = { email: string | null; storedBytes: number; storageLimit: number; subscribed: boolean };

/** The signed-in app: a sidebar on desktop, a tab row on phones. Rendered by layouts so it stays mounted. */
export function AppShell({ links, account, signOut, children }: {
  links: AppLinks;
  account: ShellAccount;
  signOut: ReactNode;
  children: ReactNode;
}) {
  return <div className="min-h-screen bg-background text-foreground md:grid md:grid-cols-[248px_minmax(0,1fr)]">
    <aside className="sticky top-0 hidden h-screen flex-col bg-white/[0.015] px-3 pt-4 pb-3 shadow-[inset_-1px_0_0_rgb(255_255_255/6%)] md:flex">
      <Brand />
      <AppNav links={links} variant="sidebar" />

      <div className="mt-auto flex flex-col gap-3">
        <StorageCard account={account} planHref={links.plan} />
        <div className="flex flex-col gap-0.5">
          <SideLink href="/" current={false} icon={<ArrowUpRight />}>blitzrecorder.com</SideLink>
        </div>
        <div className="flex items-center gap-2.5 rounded-[10px] px-2 py-2">
          <span className="grid size-7 shrink-0 place-items-center rounded-full bg-white/[0.08] text-[12px] font-semibold uppercase">
            {(account.email ?? "?").slice(0, 1)}
          </span>
          <span className="min-w-0 flex-1 truncate text-[13px] text-muted-foreground" title={account.email ?? undefined}>
            {account.email}
          </span>
          {signOut}
        </div>
      </div>
    </aside>

    <header className="sticky top-0 z-30 bg-background/80 shadow-[inset_0_-1px_0_rgb(255_255_255/6%)] backdrop-blur-xl md:hidden">
      <div className="flex h-14 items-center justify-between px-4">
        <Brand />
        {signOut}
      </div>
      <AppNav links={links} variant="tabs" />
    </header>

    <main className="min-w-0">
      <div className="mx-auto w-full max-w-[1120px] px-4 pt-8 pb-24 sm:px-8 md:px-12 md:pt-14">{children}</div>
    </main>
  </div>;
}

/** Title row shared by every page of the app. */
export function PageHeader({ title, description, actions }: { title: string; description: string; actions: ReactNode }) {
  return <div className="mb-10 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
    <div>
      <h1 className="type-title text-[clamp(1.875rem,3.4vw,2.5rem)]">{title}</h1>
      <p className="mt-2 max-w-xl text-[15px] leading-6 text-pretty text-muted-foreground">{description}</p>
    </div>
    {actions ? <div className="flex shrink-0 items-center gap-2">{actions}</div> : null}
  </div>;
}

function Brand() {
  return <Link href="/" className="flex h-9 items-center gap-2 px-2">
    <Image src={assets.macIcon} width={20} height={20} alt="" className="size-5 rounded-[22.5%]" />
    <span className="text-[14px] font-semibold tracking-[-0.01em]">BlitzRecorder</span>
  </Link>;
}

function StorageCard({ account, planHref }: { account: ShellAccount; planHref: string }) {
  const share = account.storageLimit > 0 ? Math.min(1, account.storedBytes / account.storageLimit) : 0;
  const card = "block rounded-[12px] bg-white/[0.03] p-3 shadow-[inset_0_0_0_1px_rgb(255_255_255/6%)] transition-colors hover:bg-white/[0.05]";
  if (!account.subscribed) {
    return <Link href={planHref} className={card}>
      <p className="text-[12px] font-medium">Free plan</p>
      <p className="mt-1 text-[12px] leading-5 text-faint">Links use your own Cloudflare. Upgrade for 50 GB of hosting.</p>
    </Link>;
  }
  return <Link href={planHref} className={card}>
    <div className="flex items-baseline justify-between gap-2 text-[12px]">
      <span className="font-medium">Hosting plan</span>
      <span className="text-faint tabular-nums">{formatBytes(account.storedBytes)} / {formatBytes(account.storageLimit)}</span>
    </div>
    <div className="mt-2 h-1 overflow-hidden rounded-full bg-white/[0.08]">
      <div className={cn("h-full rounded-full", share >= 0.9 ? "bg-warning" : "bg-primary")}
        style={{ width: `${Math.max(share * 100, account.storedBytes > 0 ? 2 : 0)}%` }} />
    </div>
  </Link>;
}

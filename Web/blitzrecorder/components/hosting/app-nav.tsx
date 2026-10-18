"use client";

import Link from "next/link";
import { useSelectedLayoutSegment } from "next/navigation";
import type { ReactNode } from "react";
import { CreditCard, Film, Gauge, UserRound } from "lucide-react";
import type { AppLinks, AppPage } from "@/components/hosting/app-shell";
import { cn } from "@/lib/utils";

const pages: { key: AppPage; label: string; icon: ReactNode }[] = [
  { key: "videos", label: "Videos", icon: <Film /> },
  { key: "usage", label: "Usage", icon: <Gauge /> },
  { key: "plan", label: "Plan & billing", icon: <CreditCard /> },
  { key: "account", label: "Account", icon: <UserRound /> },
];

/** The layout's child segment names the page; the videos list is the layout's own index. */
function useCurrentPage(): AppPage {
  const segment = useSelectedLayoutSegment();
  return pages.find((page) => page.key === segment)?.key ?? "videos";
}

export function AppNav({ links, variant }: { links: AppLinks; variant: "sidebar" | "tabs" }) {
  const current = useCurrentPage();
  if (variant === "tabs") {
    return <nav aria-label="App" className="flex gap-1 overflow-x-auto px-3 pb-2 [scrollbar-width:none]">
      {pages.map((item) => <Link key={item.key} href={links[item.key]} aria-current={current === item.key ? "page" : undefined}
        className={cn("inline-flex h-8 shrink-0 items-center gap-2 rounded-control px-3 text-[13px] font-medium transition-colors [&_svg]:size-3.5",
          current === item.key ? "bg-white/[0.09] text-foreground" : "text-white/55 hover:text-foreground")}>
        {item.icon}{item.label}
      </Link>)}
    </nav>;
  }
  return <nav aria-label="App" className="mt-6 flex flex-col gap-0.5">
    {pages.map((item) => <SideLink key={item.key} href={links[item.key]} current={current === item.key} icon={item.icon}>
      {item.label}
    </SideLink>)}
  </nav>;
}

export function SideLink({ href, current, icon, children }: { href: string; current: boolean; icon: ReactNode; children: ReactNode }) {
  return <Link href={href} aria-current={current ? "page" : undefined}
    className={cn("flex h-8 items-center gap-2.5 rounded-[8px] px-2 text-[13.5px] font-medium transition-colors [&_svg]:size-4 [&_svg]:shrink-0",
      current ? "bg-white/[0.08] text-foreground" : "text-white/60 hover:bg-white/[0.04] hover:text-foreground")}>
    {icon}{children}
  </Link>;
}

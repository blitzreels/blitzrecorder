import type { ReactNode } from "react";
import Link from "next/link";
import { SiteMark } from "@/components/site/site-mark";
import { cn } from "@/lib/utils";

export const navItemClass = "inline-flex h-8 items-center rounded-control px-2.5 text-[13px] font-medium text-white/60 outline-none transition-colors hover:text-white focus-visible:ring-3 focus-visible:ring-ring/40";

export const NavItem = ({ href, current, className, children, onClick }: {
  href: string; current?: boolean; className?: string; children: ReactNode; onClick?: () => void;
}) => <Link href={href} aria-current={current ? "page" : undefined} onClick={onClick}
  className={cn(navItemClass, current && "bg-fill-quiet text-foreground", className)}>
  {children}
</Link>;

/** The one site bar. Marketing pages float it. App pages stick it. */
export const SiteHeader = ({ position = "sticky", tone = "solid", compact = false, innerClassName, leading, nav, trailing, menu }: {
  position?: "fixed" | "sticky";
  tone?: "solid" | "clear" | "opaque";
  compact?: boolean;
  innerClassName?: string;
  leading?: ReactNode;
  nav?: ReactNode;
  trailing?: ReactNode;
  menu?: ReactNode;
}) => <header className={cn(
  "inset-x-0 top-0 z-40 transition-colors duration-200",
  position === "fixed" ? "fixed" : "sticky",
  tone === "opaque" ? "bg-background shadow-[inset_0_-1px_0_rgb(255_255_255/7%)]" : tone === "solid" ? "bg-background/72 shadow-[inset_0_-1px_0_rgb(255_255_255/7%)] backdrop-blur-xl backdrop-saturate-150" : "bg-transparent",
)}>
  <div className={cn("mx-auto flex h-14 items-center gap-2", innerClassName ?? "w-[min(1360px,calc(100%-32px))]")}>
    {leading}
    <SiteMark compact={compact} />
    {nav}
    {trailing && <div className="ml-auto flex min-w-0 items-center gap-2">{trailing}</div>}
  </div>
  {menu}
</header>;

import type { ReactNode } from "react";
import Link from "next/link";
import { SiteMark } from "@/components/site/site-mark";
import { cn } from "@/lib/utils";

export const navItemClass = "inline-flex h-8 items-center rounded-control px-2.5 text-sm text-muted-foreground outline-none transition-colors hover:bg-fill-quiet hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/40";

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
  "inset-x-0 top-0 z-40 border-b transition-colors duration-200",
  position === "fixed" ? "fixed" : "sticky",
  tone === "opaque" ? "border-separator bg-background" : tone === "solid" ? "glass border-separator" : "border-transparent bg-transparent",
)}>
  <div className={cn("mx-auto flex h-16 items-center gap-2", innerClassName ?? "w-[min(1180px,calc(100%-32px))]")}>
    {leading}
    <SiteMark compact={compact} />
    {nav}
    {trailing && <div className="ml-auto flex min-w-0 items-center gap-2">{trailing}</div>}
  </div>
  {menu}
</header>;

import Link from "next/link";
import type { ReactNode } from "react";
import { NavItem, SiteHeader } from "@/components/site/site-header";
import { SignOutButton, SignOutEverywhere } from "@/components/hosting/sign-out-button";
import { Button, buttonVariants } from "@/components/ui/button";
import { signInPath, videosPath } from "@/lib/hosting/paths";
import { cn } from "@/lib/utils";

const bar = "max-w-[1480px] px-4 sm:px-6";

/** Library page. Same bar as the rest of the site, with the account on the right. */
export const LibraryFrame = ({ email, sessions = 0, signOutHref, videosHref = videosPath, children }: {
  email: string | null; sessions?: number; signOutHref?: string; videosHref?: string; children: ReactNode;
}) => <main className="min-h-screen bg-background text-foreground">
  <SiteHeader
    innerClassName={bar}
    nav={<nav aria-label="Account"><NavItem href={videosHref} current>Videos</NavItem></nav>}
    trailing={email ? <>
      <span className="hidden max-w-52 truncate text-[13px] text-faint sm:inline" title={email}>{email}</span>
      {sessions > 1 && <SignOutEverywhere sessions={sessions} className={cn(buttonVariants({ variant: "ghost", size: "sm" }), "hidden lg:inline-flex")} />}
      {signOutHref
        ? <Button size="sm" variant="outline" render={<Link href={signOutHref} />}>Sign out</Button>
        : <SignOutButton className={cn(buttonVariants({ variant: "outline", size: "sm" }))} />}
    </> : <Button size="sm" render={<Link href={signInPath} />}>Sign in</Button>}
  />
  <div className={cn("mx-auto flex w-full flex-col gap-6 py-8", bar)}>
    {children}
  </div>
</main>;

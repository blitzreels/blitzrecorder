"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { DownloadButton } from "@/components/site/download-button";
import { NavItem } from "@/components/site/site-header";
import { homeLinks } from "@/components/site/site-nav";
import { useUserOS } from "@/components/site/use-user-os";
import { Button } from "@/components/ui/button";
import { TRY_URL } from "./try-url";

export function ShareNavLinks() {
  return <nav className="ml-4 hidden items-center lg:flex" aria-label="BlitzRecorder">
    {homeLinks.map((link) => <NavItem key={link.href} href={link.href}>{link.label}</NavItem>)}
  </nav>;
}

/** Visitors on a Mac get the app directly. Everyone else learns what it is first. */
export function ShareNavActions({ signInHref }: { signInHref: string }) {
  const os = useUserOS();
  return <>
    <Button variant="ghost" className="hidden sm:inline-flex" render={<Link href={signInHref} prefetch={false} />}>Sign in</Button>
    {os === "mac"
      ? <DownloadButton label="Download free" source="share_nav" size="default" className="" />
      : <Button render={<Link href={TRY_URL} />}>Get BlitzRecorder<ArrowRight /></Button>}
  </>;
}

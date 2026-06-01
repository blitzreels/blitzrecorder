"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { assets } from "@/lib/assets";

export function SiteNav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={
        "fixed inset-x-0 top-0 z-50 transition-colors duration-300 " +
        (scrolled
          ? "border-b border-border bg-background/70 backdrop-blur-xl"
          : "border-b border-transparent bg-transparent")
      }
    >
      <div className="mx-auto flex h-16 w-[min(1180px,calc(100%-32px))] items-center">
        <Link href="/" className="group flex items-center gap-2.5 font-semibold">
          <Image
            src={assets.macIcon}
            width={32}
            height={32}
            alt=""
            className="rounded-[22%] shadow-[0_0_24px_-8px_rgba(94,242,175,0.9)] transition-shadow group-hover:shadow-[0_0_30px_-6px_rgba(94,242,175,1)]"
          />
          <span className="font-display text-[17px] tracking-tight">BlitzRecorder</span>
        </Link>
        <nav
          className="ml-auto hidden items-center gap-8 text-sm font-medium text-muted-foreground md:flex"
          aria-label="Sections"
        >
          <Link className="transition-colors hover:text-foreground" href="/#how">How it works</Link>
          <Link className="transition-colors hover:text-foreground" href="/#pricing">Pricing</Link>
        </nav>
        <Button
          render={<Link href="/#pricing" />}
          className="ml-auto h-9 rounded-full px-4 shadow-[0_14px_40px_-22px_rgba(94,242,175,0.95)] md:ml-8"
        >
          Request access
        </Button>
      </div>
    </header>
  );
}

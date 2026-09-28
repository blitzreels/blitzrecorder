"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { DownloadButton, GitHubLink } from "@/components/site/download-button";
import { assets } from "@/lib/assets";
import { cn } from "@/lib/utils";

const links = [
  { href: "/#record", label: "Record" },
  { href: "/#camera", label: "iPhone" },
  { href: "/#edit", label: "Edit" },
  { href: "/#export", label: "Export" },
  { href: "/#free", label: "Free" },
];

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
      className={cn(
        "fixed inset-x-0 top-0 z-50 border-b transition-colors duration-300",
        scrolled ? "glass border-separator" : "border-transparent",
      )}
    >
      <div className="mx-auto flex h-16 w-[min(1180px,calc(100%-32px))] items-center">
        <Link href="/" className="flex items-center gap-2.5">
          <Image src={assets.macIcon} width={30} height={30} alt="" className="rounded-[22%]" />
          <span className="hidden font-display text-[17px] font-bold tracking-[-0.02em] min-[360px]:inline">
            BlitzRecorder
          </span>
        </Link>
        <nav
          className="ml-auto hidden items-center gap-7 text-sm text-muted-foreground md:flex"
          aria-label="Sections"
        >
          {links.map((link) => (
            <Link key={link.href} className="transition-colors hover:text-foreground" href={link.href}>
              {link.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-4 md:ml-8">
          <GitHubLink className="hidden text-muted-foreground transition-colors hover:text-foreground sm:inline-flex" />
          <DownloadButton label="Download" source="nav" size="default" className="" />
        </div>
      </div>
    </header>
  );
}

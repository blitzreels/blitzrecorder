"use client";

import { useEffect, useState } from "react";
import { Menu, X } from "lucide-react";
import { DownloadButton, GitHubLink } from "@/components/site/download-button";
import { NavItem, SiteHeader } from "@/components/site/site-header";
import { Button } from "@/components/ui/button";
import { videosPath } from "@/lib/hosting/paths";

const links = [
  { href: "/#record", label: "Record" },
  { href: "/#camera", label: "iPhone" },
  { href: "/#edit", label: "Edit" },
  { href: "/#export", label: "Export" },
  { href: "/#share", label: "Share" },
  { href: "/#free", label: "Free" },
  { href: videosPath, label: "Videos" },
];

export function SiteNav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return <SiteHeader
    position="fixed"
    tone={open ? "opaque" : scrolled ? "solid" : "clear"}
    nav={<nav className="ml-4 hidden items-center lg:flex" aria-label="Sections">
      {links.map((link) => <NavItem key={link.href} href={link.href}>{link.label}</NavItem>)}
    </nav>}
    trailing={<>
      <Button type="button" size="icon" variant="ghost" className="lg:hidden" aria-expanded={open} aria-label={open ? "Close menu" : "Open menu"}
        onClick={() => setOpen((value) => !value)}>
        {open ? <X /> : <Menu />}
      </Button>
      <GitHubLink className="inline-flex size-8 items-center justify-center rounded-control text-muted-foreground transition-colors hover:bg-fill-quiet hover:text-foreground" />
      <DownloadButton label="Download" source="nav" size="default" className="" />
    </>}
    menu={open ? <nav className="border-t border-separator px-4 py-2 lg:hidden" aria-label="Sections">
      <ul className="mx-auto flex w-[min(1180px,calc(100%-32px))] flex-col py-1">
        {links.map((link) => <li key={link.href}>
          <NavItem href={link.href} className="h-10 w-full" onClick={() => setOpen(false)}>{link.label}</NavItem>
        </li>)}
      </ul>
    </nav> : null}
  />;
}

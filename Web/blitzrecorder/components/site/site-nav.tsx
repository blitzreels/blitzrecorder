"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { DownloadButton, GitHubMark } from "@/components/site/download-button";
import { assets } from "@/lib/assets";
import { videosPath } from "@/lib/hosting/paths";
import { GITHUB_REPO_URL } from "@/lib/release";
import { cn } from "@/lib/utils";

/** Homepage sections, also linked from pages that live outside the homepage. */
export const homeLinks = [
  { href: "/#how", label: "How it works" },
  { href: "/#made-with", label: "Examples" },
  { href: "/#free", label: "Pricing" },
  { href: "/#camera", label: "iPhone" },
  { href: "/#faq", label: "FAQ" },
]

const linkClass = "text-[13px] font-medium text-white/60 transition-colors duration-150 hover:text-white";

/** The marketing bar: clear over the hero, frosted with a hairline once the page scrolls. */
export function SiteNav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={cn(
        "fixed inset-x-0 top-0 z-40 transition-[background-color,box-shadow] duration-200",
        scrolled || open
          ? "bg-background/72 shadow-[inset_0_-1px_0_rgb(255_255_255/7%)] backdrop-blur-xl backdrop-saturate-150"
          : "bg-transparent",
      )}
    >
      <div className="mx-auto grid h-14 w-[min(1120px,calc(100%-32px))] grid-cols-[1fr_auto_1fr] items-center">
        <Link href="/" className="flex items-center gap-2 justify-self-start" aria-label="BlitzRecorder home">
          <Image src={assets.macIcon} width={22} height={22} alt="" className="size-[22px] rounded-[22.5%]" />
          <span className="text-[15px] font-semibold tracking-[-0.02em]">BlitzRecorder</span>
        </Link>

        <nav aria-label="Sections" className="hidden items-center gap-7 lg:flex">
          {homeLinks.map((link) => (
            <Link key={link.href} href={link.href} className={linkClass}>
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="col-start-3 flex items-center gap-5 justify-self-end">
          <Link href={videosPath} className={cn(linkClass, "hidden lg:inline")}>
            My videos
          </Link>
          <a
            href={GITHUB_REPO_URL}
            target="_blank"
            rel="noopener"
            aria-label="BlitzRecorder on GitHub"
            className="hidden text-white/60 transition-colors hover:text-white sm:inline-flex"
          >
            <GitHubMark className="size-[18px]" />
          </a>
          <DownloadButton label="Download" source="nav" size="sm" className="max-sm:hidden" />
          <button
            type="button"
            aria-expanded={open}
            aria-label={open ? "Close menu" : "Open menu"}
            onClick={() => setOpen((value) => !value)}
            className="-mr-2 grid size-9 place-items-center rounded-control text-white/70 transition-colors hover:text-white lg:hidden"
          >
            <span className="relative block h-3 w-4" aria-hidden>
              <span
                className={cn(
                  "absolute inset-x-0 top-0 h-[1.5px] rounded-full bg-current transition-transform duration-200",
                  open && "translate-y-[5px] rotate-45",
                )}
              />
              <span
                className={cn(
                  "absolute inset-x-0 bottom-0 h-[1.5px] rounded-full bg-current transition-transform duration-200",
                  open && "-translate-y-[5px] -rotate-45",
                )}
              />
            </span>
          </button>
        </div>
      </div>

      {open ? (
        <nav aria-label="Sections" className="mx-auto w-[min(1120px,calc(100%-32px))] pt-2 pb-6 lg:hidden">
          <ul className="flex flex-col">
            {[...homeLinks, { href: videosPath, label: "My videos" }].map((link) => (
              <li key={link.href}>
                <Link
                  href={link.href}
                  onClick={() => setOpen(false)}
                  className="flex h-12 items-center text-[17px] font-medium text-white/80 transition-colors hover:text-white"
                >
                  {link.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      ) : null}
    </header>
  );
}

"use client";

import { useEffect } from "react";

/**
 * Progressively enhances any element tagged with `data-reveal` so it rises into
 * view on scroll. The hidden initial state lives behind `.reveal-ready` (added
 * here), so without JS — or with reduced motion — everything stays visible.
 * Stagger items with an inline `--reveal-delay` custom property.
 */
export function useReveal() {
  useEffect(() => {
    const root = document.documentElement;
    root.classList.add("reveal-ready");

    const els = Array.from(
      document.querySelectorAll<HTMLElement>("[data-reveal]")
    );

    const reduced = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;

    if (reduced || !("IntersectionObserver" in window)) {
      els.forEach((el) => el.classList.add("is-visible"));
      return;
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        }
      },
      { rootMargin: "0px 0px -12% 0px", threshold: 0.1 }
    );

    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
}

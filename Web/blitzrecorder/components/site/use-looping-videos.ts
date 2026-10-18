"use client";

import { useEffect } from "react";

/**
 * Plays every `[data-loop-video]` on the page while it is on screen and pauses it off screen,
 * so a page full of device mockups only decodes what you can see. Nothing downloads until the page has
 * loaded, so the clips never compete with the first paint. Reduced motion keeps posters.
 */
export function useLoopingVideos() {
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const videos = Array.from(document.querySelectorAll<HTMLVideoElement>("video[data-loop-video]"));
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const video = entry.target as HTMLVideoElement;
        if (entry.isIntersecting) {
          if (video.preload === "none") video.preload = "auto";
          void video.play().catch(() => undefined);
        } else {
          video.pause();
        }
      }
    }, { rootMargin: "200px 0px" });
    const start = () => { for (const video of videos) observer.observe(video); };
    if (document.readyState === "complete") start();
    else window.addEventListener("load", start, { once: true });
    return () => {
      window.removeEventListener("load", start);
      observer.disconnect();
    };
  }, []);
}

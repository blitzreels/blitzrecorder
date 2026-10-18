"use client";

import { useEffect, type RefObject } from "react";

/**
 * Calls `onProgress` with 0 when the section's top reaches the top of the viewport and 1 when
 * its bottom reaches the bottom, once per frame while scrolling. Never fires with reduced motion.
 */
export function useScrollProgress({
  ref,
  onProgress,
}: {
  ref: RefObject<HTMLElement | null>;
  onProgress: (progress: number) => void;
}) {
  useEffect(() => {
    const element = ref.current;
    if (!element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const box = element.getBoundingClientRect();
      const travel = box.height - window.innerHeight;
      onProgress(travel > 0 ? Math.min(1, Math.max(0, -box.top / travel)) : 0);
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    update();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  }, [ref, onProgress]);
}

/** 0 before `start`, 1 after `end`, eased in between. */
export function phase({ progress, start, end }: { progress: number; start: number; end: number }) {
  const t = Math.min(1, Math.max(0, (progress - start) / (end - start)));
  return t * t * (3 - 2 * t);
}

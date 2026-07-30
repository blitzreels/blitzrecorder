import type { CSSProperties } from "react";

/** Stagger a reveal; cast covers csstype not knowing CSS custom properties. */
export const revealDelay = (ms: string): CSSProperties =>
  ({ "--reveal-delay": ms }) as CSSProperties;

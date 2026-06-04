"use client";

import { useEffect, useState } from "react";

export type UserOS = "mac" | "ios" | "windows" | "linux" | "android" | "other";

function detectUserOS(): UserOS {
  const ua = navigator.userAgent;
  const platform = navigator.platform || "";
  const isTouchMac = platform === "MacIntel" && navigator.maxTouchPoints > 1;

  if (/iPhone|iPad|iPod/.test(ua) || isTouchMac) return "ios";
  if (/Mac/i.test(platform) || /Mac OS X/i.test(ua)) return "mac";
  if (/Win/i.test(platform) || /Windows/i.test(ua)) return "windows";
  if (/Android/i.test(ua)) return "android";
  if (/Linux/i.test(platform) || /Linux/i.test(ua)) return "linux";
  return "other";
}

/**
 * Best-effort client-side OS detection for tailoring the download CTA.
 * Returns null on the server and the first client paint (so SSR markup matches),
 * then resolves after mount. iPadOS reports as Mac, so we disambiguate by touch.
 */
export function useUserOS(): UserOS | null {
  const [os, setOs] = useState<UserOS | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => setOs(detectUserOS()), 0);
    return () => window.clearTimeout(id);
  }, []);

  return os;
}

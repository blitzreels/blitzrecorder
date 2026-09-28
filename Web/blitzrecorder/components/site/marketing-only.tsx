"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

export function MarketingOnly({ children }: { children: ReactNode }) {
  const path = usePathname();
  return path.startsWith("/s/") ? null : children;
}

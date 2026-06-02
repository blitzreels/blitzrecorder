"use client";

import { createContext, useContext } from "react";
import type { Release } from "@/lib/release";

const ReleaseContext = createContext<Release | null>(null);

/** Provides the latest release (fetched once in the root layout) to the tree. */
export function ReleaseProvider({
  release,
  children,
}: {
  release: Release | null;
  children: React.ReactNode;
}) {
  return <ReleaseContext.Provider value={release}>{children}</ReleaseContext.Provider>;
}

/** Latest release, or null when none is published yet. */
export function useRelease(): Release | null {
  return useContext(ReleaseContext);
}

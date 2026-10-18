"use client";

import { useLoopingVideos } from "@/components/site/use-looping-videos";

/** Drop-in for server-rendered pages that show device mockups. */
export function LoopingVideos() {
  useLoopingVideos();
  return null;
}

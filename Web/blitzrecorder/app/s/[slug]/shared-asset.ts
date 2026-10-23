import { cache } from "react";
import { sharedAsset } from "@/lib/hosting/service";

export const hasFile = ({ asset, path }: { asset: { files: { path: string }[] }; path: string }) =>
  asset.files.some((file) => file.path === path);

export const loadShared = cache(async (slug: string) => {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return null;
  return sharedAsset(slug);
});

/** Direct uploads play their MP4; older uploads were transcoded to HLS. */
export const playablePath = (asset: { files: { path: string }[] }) =>
  hasFile({ asset, path: "video.mp4" }) ? "video.mp4" : hasFile({ asset, path: "master.m3u8" }) ? "master.m3u8" : null;

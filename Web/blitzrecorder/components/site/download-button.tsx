"use client";

import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useRelease } from "@/components/site/release-context";

/**
 * Primary CTA that adapts to release state: when a GitHub Release exists it
 * downloads the macOS DMG; otherwise it falls back to the "Request access"
 * link so the page stays honest before the first public release.
 * Callers own sizing via `className` (the download and fallback states share it).
 */
export function DownloadButton({
  className,
  variant = "default",
  fallbackHref = "/#pricing",
  fallbackLabel = "Request access",
  downloadLabel = "Download for Mac",
}: {
  className?: string;
  variant?: "default" | "outline";
  fallbackHref?: string;
  fallbackLabel?: string;
  downloadLabel?: string;
}) {
  const release = useRelease();

  if (!release) {
    return (
      <Button variant={variant} render={<a href={fallbackHref} />} className={className}>
        {fallbackLabel}
      </Button>
    );
  }

  return (
    <Button variant={variant} render={<a href={release.dmgUrl} />} className={className}>
      <Download />
      {downloadLabel}
    </Button>
  );
}

/** `vX.Y.Z` linking to the release page; renders nothing until a release exists. */
export function VersionTag({ className }: { className?: string }) {
  const release = useRelease();
  if (!release) return null;
  return (
    <a href={release.htmlUrl} target="_blank" rel="noopener" className={className}>
      v{release.version}
    </a>
  );
}

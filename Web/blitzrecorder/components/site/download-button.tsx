"use client";

import { Download } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { useRelease } from "@/components/site/release-context";
import { useUserOS } from "@/components/site/use-user-os";
import { trackJourneyEvent } from "@/lib/journey-events";
import {
  FALLBACK_VERSION,
  GITHUB_REPO_URL,
  LATEST_RELEASE_URL,
} from "@/lib/release";
import { macCompatibility } from "@/lib/content";

/**
 * Primary CTA. Always offers the public website-hosted macOS DMG. Callers own
 * sizing via className.
 */
export function DownloadButton({
  className,
  variant = "default",
  label = "Download for Mac",
  source = "unknown",
}: {
  className?: string;
  variant?: "default" | "outline";
  label?: string;
  source?: string;
}) {
  const release = useRelease();
  const href = release?.dmgUrl ?? LATEST_RELEASE_URL;

  function trackDownload() {
    trackJourneyEvent({
      eventName: "download_clicked",
      area: "download",
      payload: {
        source,
        asset: "macos_dmg",
        version: release?.version ?? FALLBACK_VERSION,
      },
    });
  }

  return (
    <Button
      variant={variant}
      render={<a href={href} onClick={trackDownload} />}
      className={className}
    >
      <Download />
      {label}
    </Button>
  );
}

/** `vX.Y.Z`; falls back to the current app version. */
export function VersionTag({ className }: { className?: string }) {
  const release = useRelease();
  const version = release?.version ?? FALLBACK_VERSION;
  return <span className={className}>v{version}</span>;
}

export function GitHubMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.65 7.65 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

/** GitHub repo link with the octocat mark. */
export function GitHubLink({ className }: { className?: string }) {
  return (
    <a
      href={GITHUB_REPO_URL}
      target="_blank"
      rel="noopener"
      aria-label="BlitzRecorder on GitHub"
      className={className}
    >
      <GitHubMark className="size-5" />
    </a>
  );
}

/**
 * Small print under the download button: system requirements + version, plus a
 * platform hint for visitors who are not on a Mac. `compact` drops the
 * requirements line on phones to keep the hero short.
 */
export function DownloadMeta({
  className,
  compact = false,
}: {
  className?: string;
  compact?: boolean;
}) {
  const release = useRelease();
  const os = useUserOS();
  const version = release?.version ?? FALLBACK_VERSION;

  const hint =
    os === "ios"
      ? "BlitzRecorder runs on your Mac. Open this page on your Mac to download."
      : os === "windows" || os === "linux" || os === "android" || os === "other"
        ? "BlitzRecorder is a macOS app."
        : null;

  return (
    <div className={className}>
      <p className={"text-balance text-faint" + (compact ? " hidden sm:block" : "")}>
        {macCompatibility} · v{version}
      </p>
      {hint ? <p className="mt-1 text-balance text-faint">{hint}</p> : null}
    </div>
  );
}

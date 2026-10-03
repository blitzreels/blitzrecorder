"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, Clapperboard, Link2, Link2Off, LoaderCircle } from "lucide-react";
import { ListingButton } from "@/components/hosting/listing-button";
import { Button } from "@/components/ui/button";
import { formatTime } from "@/lib/hosting/details";
import { sharePath } from "@/lib/hosting/paths";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import { StopSharing } from "@/components/hosting/stop-sharing";

const shortDate = (iso: string) => new Date(iso).toLocaleDateString("en-US", {
  month: "short", day: "numeric", year: "numeric", timeZone: "UTC",
});

const statusLabel = (video: LibraryVideo) => {
  if (video.status === "failed") return "Failed";
  if (video.status !== "ready") return "Processing";
  return video.listed ? "Shared" : "Unlisted";
};

const SampleClip = ({ src, start, poster }: { src: string; start: number; poster: string | null }) => <video
  src={src} poster={poster ?? undefined} muted playsInline autoPlay preload="auto" className="size-full object-cover"
  onLoadedData={(event) => { event.currentTarget.currentTime = start; }}
  onTimeUpdate={(event) => {
    const video = event.currentTarget;
    if (video.currentTime < start || video.currentTime > start + 5) video.currentTime = start;
  }}
/>;

const VideoCard = ({ video, copied, onCopy }: {
  video: LibraryVideo & { clip?: { src: string; start: number } }; copied: boolean; onCopy: (slug: string) => void;
}) => {
  const ready = video.status === "ready";
  const shared = ready && video.listed;
  const pending = video.status === "queued" || video.status === "processing";
  const preview = <div className="relative aspect-video overflow-hidden bg-black shadow-[inset_0_0_0_1px_oklch(1_0_0/0.1)] transition-[filter] duration-150 group-hover/card:brightness-110 group-focus-visible/card:brightness-110">
    {video.clip ? <SampleClip src={video.clip.src} start={video.clip.start} poster={video.poster} />
      : video.poster
      // eslint-disable-next-line @next/next/no-img-element -- posters come from the media origin, not next/image
      ? <img src={video.poster} alt="" className="size-full object-cover" loading="lazy" decoding="async" />
      : <span className="flex size-full items-center justify-center text-faint">
        {pending ? <LoaderCircle size={22} className="animate-spin" /> : <Clapperboard size={22} />}
      </span>}
    {video.duration ? <span className="absolute right-2 bottom-2 rounded-inner bg-black/70 px-1.5 py-0.5 font-mono text-[11px] text-white">
      {formatTime(video.duration)}
    </span> : null}
  </div>;
  const heading = <div className="flex flex-col gap-1 px-3 pt-3">
    <h2 className="line-clamp-2 text-sm font-medium text-pretty">{video.title}</h2>
    <p className={`text-xs ${video.status === "failed" ? "text-warning" : "text-faint"}`}>{statusLabel(video)} · {shortDate(video.createdAt)}</p>
  </div>;
  return <article className="flex flex-col overflow-hidden rounded-card bg-card">
    {shared ? <Link href={sharePath(video.slug)} aria-label={`Open ${video.title}`}
      className="group/card block outline-none transition-colors hover:bg-fill-hover focus-visible:bg-fill-hover focus-visible:ring-3 focus-visible:ring-ring/40 active:opacity-75 [&_video]:pointer-events-none [&_img]:pointer-events-none">
      {preview}{heading}
    </Link> : <div>{preview}{heading}</div>}
    <div className="mt-auto flex flex-wrap items-center gap-1.5 p-3">
      {shared && <Button type="button" size="sm" variant="ghost"
        aria-label={copied ? "Link copied" : `Copy link to ${video.title}`} onClick={() => onCopy(video.slug)}>
        {copied ? <Check /> : <Link2 />} {copied ? "Copied" : "Copy link"}
      </Button>}
      {ready && <ListingButton slug={video.slug} listed={video.listed} title={video.title} />}
      <StopSharing slug={video.slug} title={video.title} current={false}
        trigger={<Button type="button" size="sm" variant="destructive" aria-label={`Stop sharing ${video.title}`} />}>
        <Link2Off /> Stop sharing
      </StopSharing>
    </div>
  </article>;
};

export const VideoLibrary = ({ videos }: { videos: Array<LibraryVideo & { clip?: { src: string; start: number } }> }) => {
  const router = useRouter();
  const processing = videos.some((video) => video.status === "queued" || video.status === "processing");
  const [copied, setCopied] = useState<string | null>(null);

  useEffect(() => {
    if (!processing) return;
    const timer = window.setInterval(() => router.refresh(), 10_000);
    return () => window.clearInterval(timer);
  }, [processing, router]);

  const copy = (slug: string) => {
    void navigator.clipboard.writeText(`${window.location.origin}${sharePath(slug)}`).then(() => {
      setCopied(slug);
      window.setTimeout(() => setCopied((value) => value === slug ? null : value), 1600);
    });
  };

  return <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
    {videos.map((video) => <li key={video.slug}>
      <VideoCard video={video} copied={copied === video.slug} onCopy={copy} />
    </li>)}
  </ul>;
};

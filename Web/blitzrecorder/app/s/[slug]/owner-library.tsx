"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  createContext, memo, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { Check, Clapperboard, Link2, Link2Off, LoaderCircle, PanelLeft, Search, X } from "lucide-react";
import { SignOutButton, SignOutEverywhere } from "@/components/hosting/sign-out-button";
import { formatTime } from "@/lib/hosting/details";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import styles from "./owner-library.module.css";
import { StopSharing } from "./stop-sharing";

type Drawer = { open: boolean; setOpen: (open: boolean) => void };

const DrawerContext = createContext<Drawer | null>(null);

const useDrawer = () => {
  const drawer = useContext(DrawerContext);
  if (!drawer) throw new Error("OwnerLibrary parts must render inside OwnerLibraryProvider.");
  return drawer;
};

export const OwnerLibraryProvider = ({ children }: { children: ReactNode }) => {
  const [open, setOpen] = useState(false);
  const value = useMemo(() => ({ open, setOpen }), [open]);
  return <DrawerContext.Provider value={value}>{children}</DrawerContext.Provider>;
};

export const OwnerLibraryToggle = ({ count }: { count: number }) => {
  const { open, setOpen } = useDrawer();
  return <button type="button" className={styles.toggle} aria-expanded={open} aria-controls="owner-library"
    onClick={() => setOpen(!open)}>
    <PanelLeft size={16} aria-hidden />
    <span>Your videos</span>
    <span className={styles.count}>{count}</span>
  </button>;
};

const shortDate = (iso: string) => new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });

const LibraryRow = memo(function LibraryRow({ video, current, copied, onCopy, onNavigate }: {
  video: LibraryVideo; current: boolean; copied: boolean; onCopy: (slug: string) => void; onNavigate: () => void;
}) {
  const ready = video.status === "ready";
  const body = <>
    <span className={styles.thumb}>
      {video.poster
        // eslint-disable-next-line @next/next/no-img-element -- posters come from the signed media origin, not next/image
        ? <img src={video.poster} alt="" loading="lazy" decoding="async" />
        : <span className={styles.thumbEmpty}>{ready ? <Clapperboard size={16} /> : <LoaderCircle size={16} className={styles.spin} />}</span>}
      {video.duration ? <span className={styles.duration}>{formatTime(video.duration)}</span> : null}
    </span>
    <span className={styles.text}>
      <span className={styles.title}>{video.title}</span>
      <span className={styles.meta}>{ready ? shortDate(video.createdAt) : "Processing…"}</span>
    </span>
  </>;
  return <li className={styles.item}>
    {ready
      ? <Link href={`/s/${video.slug}`} prefetch={false} className={styles.row} aria-current={current ? "page" : undefined}
        onClick={onNavigate}>{body}</Link>
      : <div className={styles.row} data-disabled="true">{body}</div>}
    <span className={styles.actions} data-copied={copied || undefined}>
      {ready && <button type="button" className={styles.action} data-copied={copied || undefined}
        aria-label={copied ? "Link copied" : `Copy link to ${video.title}`} title="Copy link" onClick={() => onCopy(video.slug)}>
        {copied ? <Check size={14} /> : <Link2 size={14} />}
      </button>}
      <StopSharing slug={video.slug} title={video.title} current={current}
        trigger={<button type="button" className={styles.action} aria-label={`Stop sharing ${video.title}`} title="Stop sharing" />}>
        <Link2Off size={14} />
      </StopSharing>
    </span>
  </li>;
});

export const OwnerLibrary = ({ videos, currentSlug, email, sessions }: {
  videos: LibraryVideo[]; currentSlug: string; email: string | null; sessions: number;
}) => {
  const { open, setOpen } = useDrawer();
  const router = useRouter();
  const [query, setQuery] = useState("");
  const processing = videos.some((video) => video.status !== "ready");

  useEffect(() => {
    if (!processing) return;
    const timer = window.setInterval(() => router.refresh(), 10_000);
    return () => window.clearInterval(timer);
  }, [processing, router]);
  const [copied, setCopied] = useState<string | null>(null);
  const listRef = useRef<HTMLUListElement>(null);

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return needle ? videos.filter((video) => video.title.toLowerCase().includes(needle)) : videos;
  }, [query, videos]);

  const close = useCallback(() => setOpen(false), [setOpen]);

  const copy = useCallback((slug: string) => {
    void navigator.clipboard.writeText(`${window.location.origin}/s/${slug}`).then(() => {
      setCopied(slug);
      window.setTimeout(() => setCopied((value) => value === slug ? null : value), 1600);
    });
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !(event.target as Element | null)?.closest?.("[role=dialog]")) setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, setOpen]);

  useEffect(() => {
    listRef.current?.querySelector("[aria-current=page]")?.scrollIntoView({ block: "nearest" });
  }, [currentSlug]);

  return <>
    <button type="button" className={styles.backdrop} data-open={open || undefined} aria-label="Close your videos"
      tabIndex={-1} onClick={close} />
    <aside id="owner-library" className={styles.sidebar} data-open={open || undefined} aria-label="Your videos">
      <div className={styles.head}>
        <div>
          <h2>Your videos <span className={styles.count}>{videos.length}</span></h2>
          <p className={styles.private}>Only visible to you</p>
        </div>
        <button type="button" className={styles.close} aria-label="Close" onClick={close}><X size={16} /></button>
      </div>
      {videos.length > 6 && <label className={styles.search}>
        <Search size={14} aria-hidden />
        <input type="search" value={query} placeholder="Search videos" aria-label="Search your videos"
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Escape" && query) { event.stopPropagation(); setQuery(""); } }} />
      </label>}
      <ul ref={listRef} className={styles.list}>
        {filtered.map((video) => <LibraryRow key={video.slug} video={video} current={video.slug === currentSlug}
          copied={copied === video.slug} onCopy={copy} onNavigate={close} />)}
        {filtered.length === 0 && <li className={styles.empty}>No videos match “{query}”.</li>}
      </ul>
      <div className={styles.foot}>
        <div className={styles.account}>
          <span className={styles.email} title={email ?? undefined}>{email}</span>
          <SignOutEverywhere sessions={sessions} />
        </div>
        <SignOutButton />
      </div>
    </aside>
  </>;
};

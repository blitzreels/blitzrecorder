"use client";

import { useRef } from "react";
import { Close, Play } from "@/components/site/icons";
import { trackJourneyEvent } from "@/lib/journey-events";

const FILM_SRC = "/videos/presentation.mp4";

/**
 * Click-to-play product film. The trigger overlays the hero's Mac screen; the
 * film opens in a native <dialog> lightbox so the 11 MB video only loads on
 * demand and plays at a readable size on phones.
 */
export function WatchFilm() {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  function open() {
    trackJourneyEvent({
      eventName: "film_played",
      area: "landing",
      payload: {
        source: "hero_mac_screen",
        duration_seconds: 39,
      },
    });
    dialogRef.current?.showModal();
    void videoRef.current?.play();
  }

  function close() {
    videoRef.current?.pause();
    dialogRef.current?.close();
    trackJourneyEvent({
      eventName: "film_closed",
      area: "landing",
      payload: {
        source: "hero_mac_screen",
      },
    });
  }

  function trackEnded() {
    trackJourneyEvent({
      eventName: "film_completed",
      area: "landing",
      payload: {
        source: "hero_mac_screen",
        duration_seconds: 39,
      },
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={open}
        aria-haspopup="dialog"
        aria-label="Watch the film (39 seconds)"
        className="group/play absolute inset-0 grid cursor-pointer place-items-center rounded-[10px]"
      >
        {/* hover vignette: focuses the screen and lifts the capsule */}
        <span
          aria-hidden
          className="absolute inset-0 rounded-[10px] bg-black/0 transition-colors duration-500 group-hover/play:bg-black/30"
        />
        {/* one dark frosted capsule: play disc · label · duration */}
        {/* nudged left on phones so the duration clears the floating iPhone */}
        <span className="ring-gradient relative inline-flex -translate-x-6 items-center gap-3 rounded-full bg-black/55 py-2 pr-5 pl-2 shadow-[0_24px_70px_-20px_rgba(0,0,0,0.85)] backdrop-blur-xl transition-transform duration-300 ease-out group-hover/play:scale-[1.04] sm:translate-x-0">
          <span className="relative grid size-9 place-items-center rounded-full bg-primary text-primary-foreground shadow-[0_10px_30px_-8px_rgba(94,242,175,0.9)]">
            <span
              aria-hidden
              className="absolute inset-0 rounded-full bg-primary/50"
              style={{ animation: "br-pulse 2.8s ease-out infinite" }}
            />
            <Play className="relative ml-0.5 size-3.5" />
          </span>
          <span className="text-sm font-semibold text-foreground">
            Watch the film
          </span>
          <span className="-ml-1 font-mono text-xs text-muted-foreground">
            0:39
          </span>
        </span>
      </button>

      <dialog
        ref={dialogRef}
        onClose={() => videoRef.current?.pause()}
        // Close when the backdrop (the dialog element itself) is clicked.
        onClick={(e) => e.target === e.currentTarget && close()}
        className="m-auto w-[min(1080px,94vw)] max-h-[94svh] overflow-visible bg-transparent p-0 backdrop:bg-black/85 backdrop:backdrop-blur-sm open:animate-in open:fade-in open:zoom-in-95 open:duration-300"
      >
        <div className="flex max-h-[94svh] -translate-y-12 flex-col gap-3 sm:translate-y-0">
          <div className="flex justify-end">
            <button
              type="button"
              onClick={close}
              aria-label="Close video"
              className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-full bg-white/10 px-3 text-sm font-medium text-foreground shadow-[0_12px_30px_-18px_rgba(0,0,0,0.9)] ring-1 ring-white/15 backdrop-blur-md transition-colors hover:bg-white/20"
            >
              <Close className="size-4" />
            </button>
          </div>
          <video
            ref={videoRef}
            src={FILM_SRC}
            controls
            playsInline
            preload="none"
            onEnded={trackEnded}
            className="aspect-video max-h-[calc(94svh-48px)] w-full rounded-xl bg-black object-contain ring-1 ring-white/10"
          />
        </div>
      </dialog>
    </>
  );
}

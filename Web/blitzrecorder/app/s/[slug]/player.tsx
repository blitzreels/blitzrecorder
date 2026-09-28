"use client";

import { useState } from "react";
import { Check, CircleAlert, Copy, LoaderCircle, Play, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { activeChapter, formatTime, type VideoDetails } from "@/lib/hosting/details";
import { PlayerControls } from "./player-controls";
import { VideoNotes } from "./video-notes";
import { usePlayback } from "./use-playback";
import styles from "./player.module.css";

export function SharedPlayer({ source, poster, title, width, height, duration, frameRate, details }: {
  source: string; poster: string; title: string; width: number; height: number;
  duration: number; frameRate: number | null; details: VideoDetails;
}) {
  const { videoRef, frameRef, ...playback } = usePlayback({ source, duration, details });
  const { state } = playback;
  const [copied, setCopied] = useState<string | null>(null);
  const [copyError, setCopyError] = useState(false);
  const [shareAtTime, setShareAtTime] = useState(false);
  const chapterIndex = activeChapter({ chapters: details.chapters, time: state.time });
  const hasNotes = details.transcript.length > 0 || details.chapters.length > 0;
  const share = async () => {
    const url = new URL(location.href);
    url.search = "";
    if (shareAtTime) url.searchParams.set("t", String(Math.floor(state.time)));
    try {
      await navigator.clipboard.writeText(url.href);
      setCopied(shareAtTime ? `Link copied at ${formatTime(state.time)}` : "Link copied"); setCopyError(false);
      window.setTimeout(() => setCopied(null), 2500);
    } catch { setCopyError(true); }
  };
  return <div className={`${styles.workspace} ${hasNotes ? styles.withNotes : ""}`}>
    <div className={styles.mainColumn}>
      <div ref={frameRef} className={styles.player} tabIndex={0} aria-label="Video player"
        onKeyDown={(event) => {
          if ((event.target as HTMLElement).closest("button, input, textarea, a, [role=tab]")) return;
          if (event.altKey || event.ctrlKey || event.metaKey) return;
          switch (event.key.toLowerCase()) {
            case " ": case "k": event.preventDefault(); void playback.toggle(); break;
            case "j": event.preventDefault(); playback.seek({ time: state.time - 10 }); break;
            case "l": event.preventDefault(); playback.seek({ time: state.time + 10 }); break;
            case "arrowleft": event.preventDefault(); playback.seek({ time: state.time - 5 }); break;
            case "arrowright": event.preventDefault(); playback.seek({ time: state.time + 5 }); break;
            case "m": event.preventDefault(); playback.toggleMute(); break;
            case "f": event.preventDefault(); void playback.toggleFullscreen(); break;
            case "c": if (details.transcript.length) { event.preventDefault(); playback.toggleCaptions(); } break;
          }
        }}>
        <div className={styles.screen} style={{ aspectRatio: `${width}/${height}` }}>
          <video ref={videoRef} playsInline preload="metadata" poster={poster} aria-label={title}
            onClick={() => void playback.toggle()} onDoubleClick={() => void playback.toggleFullscreen()} />
          {!state.playing && !playback.error && <button type="button" className={styles.bigPlay} aria-label={state.ended ? "Replay video" : "Play video"}
            disabled={!state.ready} onClick={() => void playback.toggle()}>
            {!state.ready ? <LoaderCircle className="animate-spin" /> : state.ended ? <RotateCcw /> : <Play fill="currentColor" />}
          </button>}
          {state.playing && state.waiting && <div className={styles.buffering} role="status" aria-label="Buffering"><LoaderCircle className="animate-spin" /></div>}
          {playback.error && <div role="alert" className={styles.error}>
            <CircleAlert /><p>{playback.error}</p><Button variant="secondary" onClick={playback.retry}>Retry playback</Button>
          </div>}
        </div>
        <PlayerControls playback={playback} chapters={details.chapters} hasTranscript={details.transcript.length > 0} />
      </div>
      {playback.notice && <p role="status" className={styles.notice}>{playback.notice}</p>}
      <div className={styles.videoInfo}>
        <div className={styles.eyebrow}><span>{formatTime(duration)}</span><span>{width} × {height}</span>
          {frameRate && <span>{Number(frameRate.toFixed(2))} fps</span>}
          {details.recordedAt && <time dateTime={details.recordedAt}>{new Intl.DateTimeFormat("en", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(details.recordedAt))}</time>}
        </div>
        <h1>{title}</h1>
        <div className={styles.infoActions}>
          <span className={styles.chapterStatus}>{chapterIndex >= 0 ? `${chapterIndex + 1} / ${details.chapters.length} · ${details.chapters[chapterIndex].title}` : "Shared with BlitzRecorder"}</span>
          <div className={styles.shareActions}>
            <label><input type="checkbox" checked={shareAtTime} onChange={(event) => setShareAtTime(event.target.checked)} />At {formatTime(state.time)}</label>
            <Button variant="outline" size="lg" onClick={() => void share()}>{copied ? <Check /> : <Copy />}{copied ? "Copied" : "Copy link"}</Button>
          </div>
        </div>
        <span role="status" className="sr-only">{copied}</span>
        {copyError && <p role="alert" className={styles.notice}>Could not copy. Copy the link from your browser’s address bar.</p>}
        {details.summary && <section className={styles.summary} aria-label="Video summary"><h2>About this video</h2><p>{details.summary}</p></section>}
      </div>
    </div>
    {hasNotes && <VideoNotes details={details} time={state.time} ready={state.ready} onSeek={playback.seek} />}
  </div>;
}

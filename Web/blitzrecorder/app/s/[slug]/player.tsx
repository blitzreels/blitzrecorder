"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { Check, CircleAlert, Clock3, Link2, LoaderCircle, Play, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { languageLabel, transcriptBrief } from "@/lib/hosting/brief";
import { activeChapter, formatTime, type VideoDetails } from "@/lib/hosting/details";
import { PlayerControls } from "./player-controls";
import { VideoNotes, type NotesTab } from "./video-notes";
import { usePlayback } from "./use-playback";
import { TRY_URL } from "./try-url";
import styles from "./player.module.css";

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

export function SharedPlayer({ source, poster, title, width, height, duration, frameRate, details, ownerActions, children }: {
  source: string; poster: string; title: string; width: number; height: number;
  duration: number; frameRate: number | null; details: VideoDetails; ownerActions?: ReactNode; children?: ReactNode;
}) {
  const { videoRef, frameRef, ...playback } = usePlayback({ source, duration, details });
  const { state } = playback;
  const [copied, setCopied] = useState<"link" | "time" | null>(null);
  const [copyError, setCopyError] = useState(false);
  const [idle, setIdle] = useState(false);
  const idleTimer = useRef<number | undefined>(undefined);
  const brief = useMemo(() => transcriptBrief({ details, duration }), [details, duration]);
  const hasNotes = details.transcript.length > 0 || details.chapters.length > 0;
  const [tab, setTab] = useState<NotesTab>(brief.long && brief.sections.length ? "summary" : details.transcript.length ? "transcript" : "chapters");
  const language = languageLabel(details.language);
  const chapterIndex = activeChapter({ chapters: details.chapters, time: state.time });

  const wake = () => {
    setIdle(false);
    window.clearTimeout(idleTimer.current);
    idleTimer.current = window.setTimeout(() => setIdle(true), 2600);
  };
  useEffect(() => () => window.clearTimeout(idleTimer.current), []);

  const share = async (atTime: boolean) => {
    const url = new URL(location.href);
    url.search = "";
    if (atTime) url.searchParams.set("t", String(Math.floor(state.time)));
    try {
      await navigator.clipboard.writeText(url.href);
      setCopied(atTime ? "time" : "link"); setCopyError(false);
      window.setTimeout(() => setCopied(null), 2200);
    } catch { setCopyError(true); }
  };
  const showChapters = () => {
    setTab("chapters");
    document.getElementById("video-notes")?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  };

  return <div className={`${styles.workspace} ${hasNotes ? styles.withNotes : ""}`}>
    <section className={styles.stage} aria-label={title}>
      <div ref={frameRef} className={styles.player} tabIndex={0} aria-label="Video player"
        data-idle={idle && state.playing ? "true" : undefined} data-playing={state.playing ? "true" : undefined}
        onPointerMove={wake} onPointerDown={wake} onPointerLeave={() => state.playing && setIdle(true)}
        onKeyDown={(event) => {
          if ((event.target as HTMLElement).closest("input, textarea, [role=menu], [role=tab]")) return;
          if (event.altKey || event.ctrlKey || event.metaKey) return;
          const key = event.key.toLowerCase();
          if ((event.target as HTMLElement).closest("button") && (key === " " || key === "enter")) return;
          if (/^[0-9]$/.test(key)) { event.preventDefault(); playback.seek({ time: state.duration * Number(key) / 10 }); return; }
          wake();
          switch (key) {
            case " ": case "k": event.preventDefault(); void playback.toggle(); break;
            case "j": event.preventDefault(); playback.seek({ time: state.time - 10 }); break;
            case "l": event.preventDefault(); playback.seek({ time: state.time + 10 }); break;
            case "arrowleft": event.preventDefault(); playback.seek({ time: state.time - 5 }); break;
            case "arrowright": event.preventDefault(); playback.seek({ time: state.time + 5 }); break;
            case "arrowup": event.preventDefault(); playback.changeVolume({ volume: Math.min(1, state.volume + 0.1) }); break;
            case "arrowdown": event.preventDefault(); playback.changeVolume({ volume: Math.max(0, state.volume - 0.1) }); break;
            case "home": event.preventDefault(); playback.seek({ time: 0 }); break;
            case "end": event.preventDefault(); playback.seek({ time: state.duration }); break;
            case "<": case ">": {
              event.preventDefault();
              const index = SPEEDS.indexOf(state.speed);
              const next = SPEEDS[Math.max(0, Math.min(SPEEDS.length - 1, (index < 0 ? 2 : index) + (key === ">" ? 1 : -1)))];
              playback.changeSpeed({ speed: next });
              break;
            }
            case "m": event.preventDefault(); playback.toggleMute(); break;
            case "f": event.preventDefault(); void playback.toggleFullscreen(); break;
            case "c": if (details.transcript.length) { event.preventDefault(); playback.toggleCaptions(); } break;
          }
        }}>
        <div className={styles.screen} style={{ aspectRatio: `${width}/${height}` }}>
          <video ref={videoRef} playsInline preload="metadata" poster={poster || undefined} aria-label={title}
            onClick={() => void playback.toggle()} onDoubleClick={() => void playback.toggleFullscreen()} />
          {!state.playing && !state.ended && !playback.error && <button type="button" className={styles.bigPlay}
            aria-label="Play video" disabled={!state.ready} onClick={() => void playback.toggle()}>
            {!state.ready ? <LoaderCircle className="animate-spin" /> : <Play fill="currentColor" />}
          </button>}
          {state.ended && !playback.error && <div className={styles.endCard}>
            <p>Recorded and edited with BlitzRecorder</p>
            <h2>Make your own videos like this, free.</h2>
            <div>
              <Button size="lg" render={<Link href={TRY_URL} />}>Try BlitzRecorder free</Button>
              <Button variant="outline" size="lg" onClick={() => void playback.toggle()}><RotateCcw />Replay</Button>
            </div>
          </div>}
          {state.playing && state.waiting && <div className={styles.buffering} role="status" aria-label="Buffering">
            <LoaderCircle className="animate-spin" />
          </div>}
          {playback.error && <div role="alert" className={styles.error}>
            <CircleAlert /><p>{playback.error}</p><Button variant="outline" onClick={playback.retry}>Try again</Button>
          </div>}
        </div>
        <PlayerControls playback={playback} speeds={SPEEDS} chapters={details.chapters}
          hasTranscript={details.transcript.length > 0} onShowChapters={showChapters} />
      </div>
      {playback.notice && <p role="status" className={styles.notice}>{playback.notice}</p>}

      <div className={styles.videoInfo}>
        <div className={styles.heading}>
          {poster &&
            // eslint-disable-next-line @next/next/no-img-element -- posters come from the signed media origin, not next/image
            <img className={styles.posterThumb} src={poster} alt="" />}
          <div className={styles.headingBody}>
            <h1>{title}</h1>
            <p className={styles.meta}>
              <span>{formatTime(duration)}</span>
              <span>{Math.max(width, height) >= 2160 ? "4K" : `${Math.min(width, height)}p`}</span>
              {frameRate && <span>{Math.round(frameRate)} fps</span>}
              {details.recordedAt && <time dateTime={details.recordedAt}>
                {new Intl.DateTimeFormat("en", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(details.recordedAt))}
              </time>}
              {language && <span>{language}</span>}
              {brief.speakers.slice(0, 4).map((speaker) => <span key={speaker.name}>
                {speaker.name}{brief.speakers.length > 1 ? ` ${speaker.percent}%` : ""}
              </span>)}
              {brief.speakers.length > 4 && <span>+{brief.speakers.length - 4}</span>}
              {chapterIndex >= 0 && <span className={styles.metaChapter}>Chapter {chapterIndex + 1} of {details.chapters.length}</span>}
            </p>
          </div>
        </div>
        <div className={styles.infoRow}>
          <div className={styles.shareActions}>
            {ownerActions}
            <Button variant="ghost" onClick={() => void share(true)} disabled={state.time < 1}
              title="Copy a link that starts at the current moment">
              {copied === "time" ? <Check /> : <Clock3 />}
              <span className="tabular-nums">{copied === "time" ? "Copied" : `Copy at ${formatTime(state.time)}`}</span>
            </Button>
            <Button variant="outline" onClick={() => void share(false)}>
              {copied === "link" ? <Check /> : <Link2 />}{copied === "link" ? "Copied" : "Copy link"}
            </Button>
          </div>
        </div>
        <span role="status" className="sr-only">{copied ? "Link copied" : ""}</span>
        {copyError && <p role="alert" className={styles.notice}>Could not copy. Copy the link from your browser’s address bar.</p>}
        {brief.lead && <section className={styles.summary} aria-label="Summary">
          <h2>Summary</h2><p>{brief.lead}</p>
        </section>}
        {children}
      </div>
    </section>
    {hasNotes && <VideoNotes details={details} brief={brief} time={state.time} duration={state.duration} ready={state.ready} playing={state.playing}
      tab={tab} onTabChange={setTab} onSeek={playback.seek} />}
  </div>;
}

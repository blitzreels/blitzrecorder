"use client";

import { useEffect, useRef, useState } from "react";
import { AudioLines, Film, Pause, Play, Volume2, VolumeX } from "lucide-react";
import { LandingSection } from "@/components/site/landing/landing-section";
import { realTake, realTakeLevels, realTakePauses } from "@/components/site/landing/real-take";
import { Button } from "@/components/ui/button";
import { formatTime } from "@/lib/hosting/details";
import { trackJourneyEvent } from "@/lib/journey-events";
import { cn } from "@/lib/utils";

const TAKE = realTake.duration;
const PAUSED = realTakePauses.reduce((sum, [start, end]) => sum + end - start, 0);
const LEVEL_SECONDS = TAKE / realTakeLevels.length;
const TILE_HEIGHT = 54;
const TILE_WIDTH = (TILE_HEIGHT * 16) / 9;
const STRIP_FRAMES = Math.round(TAKE / realTake.stripFrameSeconds);
const TRIMMED_LABEL = Math.round(TAKE - PAUSED);

type Segment = { start: number; end: number; silent: boolean };

const SEGMENTS: Segment[] = (() => {
  const segments: Segment[] = [];
  let cursor = 0;
  for (const [start, end] of realTakePauses) {
    if (start > cursor) segments.push({ start: cursor, end: start, silent: false });
    segments.push({ start, end, silent: true });
    cursor = end;
  }
  if (cursor < TAKE) segments.push({ start: cursor, end: TAKE, silent: false });
  return segments;
})();

/** Where a moment of the take sits on the timeline once the pauses are cut. */
function toTimeline({ source, trimmed }: { source: number; trimmed: boolean }) {
  if (!trimmed) return source;
  let removed = 0;
  for (const [start, end] of realTakePauses) {
    if (source >= end) removed += end - start;
    else if (source > start) return start - removed;
  }
  return source - removed;
}

function toSource({ position, trimmed }: { position: number; trimmed: boolean }) {
  if (!trimmed) return position;
  let elapsed = 0;
  for (const segment of SEGMENTS) {
    if (segment.silent) continue;
    const length = segment.end - segment.start;
    if (position <= elapsed + length) return segment.start + position - elapsed;
    elapsed += length;
  }
  return TAKE;
}

function pauseAt(source: number) {
  return realTakePauses.find(([start, end]) => source >= start && source < end) ?? null;
}

/** The editor's timeline on the first two minutes of a real take, cutting the pauses the app finds in it. */
export function EditChapter() {
  const video = useRef<HTMLVideoElement>(null);
  const tracks = useRef<HTMLDivElement>(null);
  const [trimmed, setTrimmed] = useState(false);
  const [time, setTime] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [muted, setMuted] = useState(true);
  const [trackWidth, setTrackWidth] = useState(0);
  const duration = trimmed ? TAKE - PAUSED : TAKE;
  const marks = Array.from({ length: Math.floor(duration / 30) + 1 }, (_, index) => index * 30);

  useEffect(() => {
    const element = tracks.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setTrackWidth(entry.contentRect.width));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const element = video.current;
    if (!element) return;
    let frame = 0;
    const tick = () => {
      const pause = trimmed ? pauseAt(element.currentTime) : null;
      if (pause) element.currentTime = pause[1] >= TAKE ? 0 : pause[1];
      setTime(element.currentTime);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [trimmed]);

  function toggleCut() {
    setTrimmed((value) => !value);
    trackJourneyEvent({ eventName: "landing_demo_changed", area: "landing", payload: { demo: "timeline", control: "silence", value: !trimmed } });
  }

  function togglePlay() {
    const element = video.current;
    if (!element) return;
    if (element.paused) void element.play().catch(() => undefined);
    else element.pause();
  }

  function seek(clientX: number) {
    const element = video.current;
    const area = tracks.current;
    if (!element || !area) return;
    const rect = area.getBoundingClientRect();
    const fraction = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
    element.currentTime = Math.min(TAKE - 0.05, toSource({ position: fraction * duration, trimmed }));
    setTime(element.currentTime);
  }

  const playhead = (toTimeline({ source: time, trimmed }) / duration) * 100;
  const pixelsPerSecond = trackWidth / duration;

  return (
    <LandingSection
      id="edit"
      section="edit"
      title="Finish the edit in one click."
      intro="These are the first two minutes of a real take. BlitzRecorder found every pause. Press the button to cut them all."
      action={null}
    >
      <div className="product-surface overflow-hidden rounded-[16px] bg-[#0e0e10]">
        <div className="flex flex-wrap items-center justify-between gap-4 px-4 py-3.5 shadow-[inset_0_-1px_0_rgb(255_255_255/6%)] sm:px-5">
          <p className="flex items-baseline gap-3 text-[14px]" aria-live="polite">
            <span className="font-semibold">{trimmed ? "Pauses cut" : `${realTakePauses.length} pauses found`}</span>
            <span className="text-muted-foreground tabular-nums">
              {trimmed ? `${formatTime(TRIMMED_LABEL)}, down from ${formatTime(TAKE)}` : formatTime(TAKE)}
            </span>
            {trimmed ? <span className="font-medium text-primary tabular-nums">−{formatTime(TAKE - TRIMMED_LABEL)}</span> : null}
          </p>
          <Button size="sm" variant={trimmed ? "outline" : "default"} aria-pressed={trimmed} onClick={toggleCut}>
            {trimmed ? "Restore pauses" : `Cut ${realTakePauses.length} pauses`}
          </Button>
        </div>

        <div className="px-4 pt-4 sm:px-5 sm:pt-5">
          <div className="relative mx-auto aspect-video max-w-[640px] overflow-hidden rounded-[8px] bg-black">
            <video ref={video} data-loop-video src={realTake.src} poster={realTake.poster} muted={muted} loop playsInline
              preload="none" aria-label="The first two minutes of a real take, filmed with BlitzRecorder"
              onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)} className="absolute inset-0 size-full object-cover" />
          </div>
          <div className="mx-auto mt-3 flex max-w-[640px] items-center justify-between">
            <Button size="sm" variant="ghost" onClick={togglePlay} aria-label={playing ? "Pause" : "Play"}>
              {playing ? <Pause /> : <Play />}
              <span className="font-mono text-[12px] tabular-nums">
                {formatTime(toTimeline({ source: time, trimmed }))} / {formatTime(duration)}
              </span>
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setMuted((value) => !value)} aria-pressed={!muted}>
              {muted ? <VolumeX /> : <Volume2 />}
              {muted ? "Sound off" : "Sound on"}
            </Button>
          </div>
        </div>

        <div className="overflow-x-auto">
          <div className="grid min-w-[620px] grid-cols-[104px_minmax(0,1fr)] gap-x-0 px-4 pt-2 pb-5 sm:px-5">
            <div className="flex flex-col justify-end gap-2 pb-0.5">
              <RowLabel icon={<Film />} label="Video" tint="text-primary" height="h-[54px]" />
              <RowLabel icon={<AudioLines />} label="Mic" tint="text-track-mic" height="h-12" />
            </div>
            <div ref={tracks} className="relative cursor-pointer touch-none select-none"
              onPointerDown={(event) => { event.currentTarget.setPointerCapture(event.pointerId); seek(event.clientX); }}
              onPointerMove={(event) => { if (event.currentTarget.hasPointerCapture(event.pointerId)) seek(event.clientX); }}>
              <div className="relative h-6 text-[11px] text-white/45 tabular-nums">
                {marks.map((second) => <span key={second} className="absolute top-1 -translate-x-1/2 first:translate-x-0 transition-[left] duration-500 ease-out-expo"
                  style={{ left: `${(second / duration) * 100}%` }}>{formatTime(second)}</span>)}
              </div>
              <div className="flex flex-col gap-2">
                <Track trimmed={trimmed} kind="video" pixelsPerSecond={pixelsPerSecond} />
                <Track trimmed={trimmed} kind="mic" pixelsPerSecond={pixelsPerSecond} />
              </div>
              <div aria-hidden className="pointer-events-none absolute top-5 bottom-0 w-0.5 -translate-x-1/2 bg-primary"
                style={{ left: `${playhead}%` }} />
            </div>
          </div>
        </div>
      </div>
    </LandingSection>
  );
}

function RowLabel({ icon, label, tint, height }: { icon: React.ReactNode; label: string; tint: string; height: string }) {
  return <span className={cn("flex items-center gap-2 text-[13px] font-medium [&_svg]:size-4", height)}>
    <span className={tint}>{icon}</span>{label}
  </span>;
}

function Track({ trimmed, kind, pixelsPerSecond }: { trimmed: boolean; kind: "video" | "mic"; pixelsPerSecond: number }) {
  return (
    <div className={cn("relative flex overflow-hidden rounded-[8px]", kind === "video" ? "h-[54px] bg-black" : "h-12 bg-track-mic/[0.12]")}>
      {SEGMENTS.map((segment) => {
        const seconds = segment.end - segment.start;
        const hidden = trimmed && segment.silent;
        return (
          <div key={segment.start} className="relative min-w-0 overflow-hidden transition-[flex-grow] duration-500 ease-out-expo"
            style={{ flexGrow: hidden ? 0 : seconds, flexBasis: 0 }}>
            {kind === "video"
              ? <Filmstrip segment={segment} pixelsPerSecond={pixelsPerSecond} />
              : <Waveform segment={segment} />}
            {segment.silent ? <div className="absolute inset-0 bg-record/25 shadow-[inset_0_0_0_1px_rgb(255_69_69/45%)]" /> : null}
          </div>
        );
      })}
    </div>
  );
}

/** One thumbnail per tile, each showing the frame at the moment it sits over, like the app's video track. */
function Filmstrip({ segment, pixelsPerSecond }: { segment: Segment; pixelsPerSecond: number }) {
  if (pixelsPerSecond <= 0) return null;
  const count = Math.ceil(((segment.end - segment.start) * pixelsPerSecond) / TILE_WIDTH);
  return (
    <div className="absolute inset-y-0 left-0 flex">
      {Array.from({ length: count }, (_, index) => {
        const second = segment.start + (index * TILE_WIDTH) / pixelsPerSecond;
        const frame = Math.min(STRIP_FRAMES - 1, Math.floor(second / realTake.stripFrameSeconds));
        return <div key={index} className="h-full shrink-0 bg-no-repeat" style={{
          width: TILE_WIDTH, backgroundImage: `url(${realTake.strip})`,
          backgroundSize: `${STRIP_FRAMES * TILE_WIDTH}px 100%`, backgroundPosition: `${-frame * TILE_WIDTH}px 0`,
        }} />;
      })}
    </div>
  );
}

function Waveform({ segment }: { segment: Segment }) {
  const first = Math.floor(segment.start / LEVEL_SECONDS);
  const levels = realTakeLevels.slice(first, Math.max(first + 1, Math.ceil(segment.end / LEVEL_SECONDS)));
  return (
    <svg aria-hidden viewBox={`0 0 ${levels.length} 100`} preserveAspectRatio="none"
      className={cn("absolute inset-0 size-full text-track-mic", segment.silent ? "opacity-35" : "opacity-90")}>
      {levels.map((level, index) => {
        const height = Math.max(4, level * 92);
        return <rect key={index} x={index + 0.2} width={0.6} y={50 - height / 2} height={height} fill="currentColor" />;
      })}
    </svg>
  );
}

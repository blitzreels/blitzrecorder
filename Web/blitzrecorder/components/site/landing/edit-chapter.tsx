"use client";

import { useMemo, useState } from "react";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterHeader, ChapterPoints, chapters, type ChapterPoint } from "@/components/site/landing/chapter";
import { trackJourneyEvent } from "@/lib/journey-events";
import { assets } from "@/lib/assets";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export const TAKE_SECONDS = 114;
const SILENCES: [number, number][] = [
  [9, 13],
  [26, 31],
  [43, 47],
  [58, 64],
  [77, 81],
  [92, 98],
  [106, 109],
];

type Segment = { start: number; end: number; silent: boolean };

function buildSegments(): Segment[] {
  const segments: Segment[] = [];
  let cursor = 0;
  for (const [start, end] of SILENCES) {
    if (start > cursor) segments.push({ start: cursor, end: start, silent: false });
    segments.push({ start, end, silent: true });
    cursor = end;
  }
  if (cursor < TAKE_SECONDS) segments.push({ start: cursor, end: TAKE_SECONDS, silent: false });
  return segments;
}

function seeded(seed: number) {
  let value = seed;
  return () => {
    value = (value * 16807) % 2147483647;
    return value / 2147483647;
  };
}

export function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

const SEGMENTS = buildSegments();

export const silentSeconds = SILENCES.reduce((sum, [start, end]) => sum + end - start, 0);

const points: ChapterPoint[] = [
  {
    title: "Transcripts on your Mac",
    body: "Speakers stay apart, including people on a call. Switch to Whisper Medium for accuracy or retranscribe an old take.",
  },
  {
    title: "Cuts you can see",
    body: "Waveforms, red silence markers, and hover scrubbing. Delete a range or extend a clip, and undo any step.",
  },
  {
    title: "Layouts, text, and zoom",
    body: "Change the composition for one segment, add titles, and zoom into the screen where the detail matters.",
  },
];

export function EditChapter() {
  const [trimmed, setTrimmed] = useState(false);
  const duration = trimmed ? TAKE_SECONDS - silentSeconds : TAKE_SECONDS;

  return (
    <Section id="edit" className="scroll-mt-24 py-16 sm:py-20">
      <JourneySectionView area="landing" section="edit" payload={{ page: "home" }} />
      <ChapterHeader
        mark={chapters.edit}
        title="Cut the pauses in one click."
        lede="Every take opens on a timeline with the screen, camera, and audio on separate tracks, so you can edit it again later. Try it below."
        aside={null}
      />

      <div data-reveal className="panel app-surface mt-10 overflow-hidden rounded-card sm:mt-14">
        <div className="flex flex-wrap items-center justify-between gap-4 border-b border-separator px-4 py-3 sm:px-5">
          <div className="flex items-baseline gap-3">
            <span className="label-mono text-faint">Duration</span>
            <span className="font-mono text-sm tabular-nums">
              <span className={cn("transition-colors", trimmed ? "text-faint line-through" : "text-foreground")}>
                {formatTime(TAKE_SECONDS)}
              </span>
              {trimmed ? <span className="ml-2 text-primary">{formatTime(duration)}</span> : null}
            </span>
          </div>
          <Button
            variant={trimmed ? "outline" : "default"}
            aria-pressed={trimmed}
            onClick={() => {
              setTrimmed((value) => !value);
              trackJourneyEvent({
                eventName: "landing_demo_changed",
                area: "landing",
                payload: { demo: "timeline", control: "silence", value: !trimmed },
              });
            }}
          >
            {trimmed ? "Restore silences" : `Remove ${SILENCES.length} silences`}
          </Button>
        </div>

        <div className="overflow-x-auto">
          <div className="min-w-[640px] px-4 pt-4 pb-5 sm:px-5">
            <div className="grid grid-cols-[88px_1fr] gap-x-3 gap-y-1.5">
              <span />
              <div className="ruler h-3 opacity-80" />
              <TrackLabel label="Screen" />
              <Track segments={SEGMENTS} trimmed={trimmed} kind="screen" />
              <TrackLabel label="Camera" />
              <Track segments={SEGMENTS} trimmed={trimmed} kind="camera" />
              <TrackLabel label="Mic" />
              <Track segments={SEGMENTS} trimmed={trimmed} kind="mic" />
              <TrackLabel label="Mac audio" />
              <Track segments={SEGMENTS} trimmed={trimmed} kind="system" />
            </div>
          </div>
        </div>
      </div>

      <ChapterPoints points={points} />
    </Section>
  );
}

function TrackLabel({ label }: { label: string }) {
  return <span className="self-center truncate text-xs font-medium text-faint">{label}</span>;
}

type TrackKind = "screen" | "camera" | "mic" | "system";

function Track({
  segments,
  trimmed,
  kind,
}: {
  segments: Segment[];
  trimmed: boolean;
  kind: TrackKind;
}) {
  const media = kind === "screen" || kind === "camera";
  return (
    <div className="relative flex h-10 overflow-hidden rounded-inner bg-fill-card">
      {segments.map((segment) => {
        const seconds = segment.end - segment.start;
        const hidden = trimmed && segment.silent;
        return (
          <div
            key={segment.start}
            className="relative min-w-0 overflow-hidden transition-[flex-grow] duration-700 ease-out-expo"
            style={{ flexGrow: hidden ? 0 : seconds, flexBasis: 0 }}
          >
            {media ? (
              <div
                className="absolute inset-0 bg-repeat-x"
                style={{
                  backgroundImage: `url(${kind === "screen" ? assets.screenTake.src : assets.cameraTake.src})`,
                  backgroundSize: kind === "screen" ? "48px 40px" : "71px 40px",
                  backgroundPosition: `${-segment.start * 7}px 0`,
                  opacity: 0.85,
                }}
              />
            ) : (
              <Waveform seconds={seconds} seed={segment.start + (kind === "mic" ? 7 : 101)} silent={segment.silent} kind={kind} />
            )}
            {segment.silent ? <div className="hatch absolute inset-0 bg-black/45" /> : null}
          </div>
        );
      })}
      {kind === "screen" ? (
        <div aria-hidden className="pointer-events-none absolute inset-y-0 w-px bg-primary [animation:br-playhead_14s_linear_infinite]" />
      ) : null}
    </div>
  );
}

function Waveform({
  seconds,
  seed,
  silent,
  kind,
}: {
  seconds: number;
  seed: number;
  silent: boolean;
  kind: "mic" | "system";
}) {
  const bars = useMemo(() => {
    const random = seeded(seed * 97 + 13);
    return Array.from({ length: seconds * 2 }, () => {
      if (silent) return 4 + random() * 6;
      const base = kind === "mic" ? 28 : 16;
      return base + random() * (kind === "mic" ? 62 : 44);
    });
  }, [seconds, seed, silent, kind]);

  return (
    <div
      className={cn(
        "absolute inset-0 flex items-center justify-around gap-px px-px",
        kind === "mic" ? "bg-track-mic/[0.08] text-track-mic" : "bg-track-system/[0.07] text-track-system",
      )}
    >
      {bars.map((height, index) => (
        <span key={index} className="w-[2px] shrink-0 rounded-full bg-current" style={{ height: `${height}%`, opacity: silent ? 0.4 : 0.9 }} />
      ))}
    </div>
  );
}

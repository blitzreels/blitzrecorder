"use client";

import { useState } from "react";
import { ArrowUpRight } from "@/components/site/icons";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterHeader, ChapterPoints, chapters, type ChapterPoint } from "@/components/site/landing/chapter";
import { TAKE_SECONDS, formatTime, silentSeconds } from "@/components/site/landing/edit-chapter";
import { trackJourneyEvent } from "@/lib/journey-events";
import { cn } from "@/lib/utils";

type Resolution = "1080p" | "4K";
type FrameRate = 30 | 60;

const MEGABITS: Record<Resolution, Record<FrameRate, number>> = {
  "1080p": { 30: 12, 60: 18 },
  "4K": { 30: 40, 60: 60 },
};

const points: ChapterPoint[] = [
  { title: "Up to 4K at 60 fps", body: "Metal rendering and hardware encoding keep exports quick." },
  { title: "Speed up slow talk", body: "Export from 1.0x to 2.0x in 0.1 steps without touching the edit." },
  { title: "Captions with BlitzReels", body: "Sign in once, send the MP4, and get captions and B-roll back." },
];

const EDITED_SECONDS = TAKE_SECONDS - silentSeconds;

function trackExport({ control, value }: { control: string; value: string | number }) {
  trackJourneyEvent({
    eventName: "landing_demo_changed",
    area: "landing",
    payload: { demo: "export", control, value },
  });
}

export function ExportChapter() {
  const [resolution, setResolution] = useState<Resolution>("4K");
  const [fps, setFps] = useState<FrameRate>(60);
  const [speed, setSpeed] = useState(1.2);

  const seconds = EDITED_SECONDS / speed;
  const megabytes = (MEGABITS[resolution][fps] * seconds) / 8;

  return (
    <Section id="export" className="scroll-mt-24 py-16 sm:py-20">
      <JourneySectionView area="landing" section="export" payload={{ page: "home" }} />
      <ChapterHeader
        mark={chapters.export}
        title="Export in 4K and post anywhere."
        lede="Save an MP4 at up to 60 fps and up to 2x speed. The size estimate updates as you go."
        aside={
          <BlitzReelsLink
            content="landing_export"
            className="group inline-flex items-center gap-1.5 self-start text-sm font-medium text-primary"
          >
            See what BlitzReels does
            <ArrowUpRight className="size-4 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
          </BlitzReelsLink>
        }
      />

      <div data-reveal className="panel app-surface mt-10 rounded-card p-5 sm:mt-14 sm:p-7">
        <div className="grid gap-6 md:grid-cols-3">
          <Segmented
            legend="Resolution"
            options={["1080p", "4K"] as const}
            value={resolution}
            format={(value) => value}
            onChange={(value) => {
              setResolution(value);
              trackExport({ control: "resolution", value });
            }}
          />
          <Segmented
            legend="Frame rate"
            options={[30, 60] as const}
            value={fps}
            format={(value) => `${value} fps`}
            onChange={(value) => {
              setFps(value);
              trackExport({ control: "fps", value });
            }}
          />
          <div>
            <div className="flex items-baseline justify-between">
              <label htmlFor="export-speed" className="text-xs text-faint">
                Speed
              </label>
              <span className="font-mono text-[13px] text-foreground tabular-nums">{speed.toFixed(1)}×</span>
            </div>
            <input
              id="export-speed"
              type="range"
              min={1}
              max={2}
              step={0.1}
              value={speed}
              onChange={(event) => setSpeed(Number(event.target.value))}
              onPointerUp={() => trackExport({ control: "speed", value: speed })}
              className="mt-4 w-full accent-primary"
            />
          </div>
        </div>
        <dl className="mt-7 grid grid-cols-3 gap-4 border-t border-separator pt-5">
          <Readout term="Length" value={formatTime(seconds)} />
          <Readout term="Size" value={megabytes >= 1000 ? `${(megabytes / 1000).toFixed(1)} GB` : `${Math.round(megabytes)} MB`} />
          <Readout term="Format" value="MP4" />
        </dl>
      </div>

      <ChapterPoints points={points} />
    </Section>
  );
}

function Readout({ term, value }: { term: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-faint">{term}</dt>
      <dd className="mt-1 font-mono text-lg text-foreground tabular-nums sm:text-xl">{value}</dd>
    </div>
  );
}

function Segmented<T extends string | number>({
  legend,
  options,
  value,
  format,
  onChange,
}: {
  legend: string;
  options: readonly T[];
  value: T;
  format: (value: T) => string;
  onChange: (value: T) => void;
}) {
  return (
    <fieldset>
      <legend className="text-xs text-faint">{legend}</legend>
      <div className="mt-2 grid grid-cols-2 gap-0.5 rounded-control bg-fill-control p-0.5">
        {options.map((option) => (
          <button
            key={option}
            type="button"
            aria-pressed={value === option}
            onClick={() => onChange(option)}
            className={cn(
              "h-[30px] rounded-inner font-mono text-[13px] transition-colors",
              value === option ? "bg-fill-selected text-foreground" : "text-faint hover:text-foreground",
            )}
          >
            {format(option)}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

"use client";

import Image from "next/image";
import { useState } from "react";
import { ArrowUpRight } from "@/components/site/icons";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterHeader, chapters } from "@/components/site/landing/chapter";
import { TAKE_SECONDS, formatTime, silentSeconds } from "@/components/site/landing/edit-chapter";
import { trackJourneyEvent } from "@/lib/journey-events";
import { assets } from "@/lib/assets";
import { cn } from "@/lib/utils";

type Resolution = "1080p" | "4K";
type FrameRate = 30 | 60;

const MEGABITS: Record<Resolution, Record<FrameRate, number>> = {
  "1080p": { 30: 12, 60: 18 },
  "4K": { 30: 40, 60: 60 },
};

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
        title="Export once. Post it anywhere."
        lede="Save an MP4 up to 4K at 60 fps, sped up to 2x if you talk slowly. Or send it to BlitzReels for captions and B-roll."
        aside={null}
      />

      <div className="mt-10 grid sm:mt-14 grid gap-6 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
        <div data-reveal className="panel rounded-card p-5 sm:p-7">
          <p className="label-mono text-faint">Export</p>

          <div className="mt-6 grid gap-6 sm:grid-cols-2">
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
          </div>

          <div className="mt-7">
            <div className="flex items-baseline justify-between">
              <label htmlFor="export-speed" className="label-mono text-faint">
                Speed
              </label>
              <span className="font-mono text-sm text-foreground tabular-nums">{speed.toFixed(1)}×</span>
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
              className="mt-3 w-full accent-primary"
            />
            <div className="mt-1 flex justify-between font-mono text-[11px] text-faint">
              <span>1.0×</span>
              <span>2.0×</span>
            </div>
          </div>

          <dl className="mt-7 grid grid-cols-3 gap-4 border-t border-separator pt-5">
            <Readout term="Length" value={formatTime(seconds)} />
            <Readout term="Size" value={megabytes >= 1000 ? `${(megabytes / 1000).toFixed(1)} GB` : `${Math.round(megabytes)} MB`} />
            <Readout term="Format" value="MP4" />
          </dl>
        </div>

        <div data-reveal className="panel flex flex-col rounded-card p-5 sm:p-7">
          <p className="label-mono text-faint">Optional</p>
          <Image
            src={assets.blitzreelsWordmark}
            alt="BlitzReels"
            width={187}
            height={28}
            className="mt-6 h-7 w-auto self-start"
          />
          <p className="mt-5 text-[15px] leading-6 text-muted-foreground">
            Sign in once from the app, then send the finished MP4. BlitzReels
            finds the best moments, reframes them for vertical, and adds captions.
          </p>
          <BlitzReelsLink
            content="landing_export"
            className="group mt-auto inline-flex items-center gap-1.5 self-start pt-8 text-sm font-medium text-primary"
          >
            See what BlitzReels does
            <ArrowUpRight className="size-4 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
          </BlitzReelsLink>
        </div>
      </div>
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

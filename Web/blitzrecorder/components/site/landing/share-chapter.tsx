"use client";

import Image from "next/image";
import { useState } from "react";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterHeader, ChapterPoints, chapters, type ChapterPoint } from "@/components/site/landing/chapter";
import { formatTime } from "@/components/site/landing/edit-chapter";
import { HOSTING_PLAN } from "@/lib/hosting/plan";
import { trackJourneyEvent } from "@/lib/journey-events";
import { assets } from "@/lib/assets";
import { cn } from "@/lib/utils";

const DURATION = 104;

type Tab = "transcript" | "chapters";
type Cue = { start: number; speaker: string; text: string };
type Chapter = { start: number; title: string };

const CUES: Cue[] = [
  { start: 0, speaker: "Alex", text: "Thanks for joining. Let me share my screen." },
  { start: 18, speaker: "Alex", text: "This is the new release board. Every update lands here first." },
  { start: 52, speaker: "Sam", text: "Can the feedback inbox tag the customer automatically?" },
  { start: 61, speaker: "Alex", text: "It does. Watch what happens when I paste a request." },
  { start: 88, speaker: "Alex", text: "That's it. The transcript is under the link if you want to skim." },
];

const CHAPTERS: Chapter[] = [
  { start: 0, title: "Intro" },
  { start: 18, title: "The release board" },
  { start: 52, title: "Feedback inbox" },
  { start: 88, title: "Wrap-up" },
];

const price = new Intl.NumberFormat("en", {
  style: "currency",
  currency: HOSTING_PLAN.currency,
  maximumFractionDigits: 0,
}).format(HOSTING_PLAN.amount / 100);
const storage = `${HOSTING_PLAN.storageBytes / 1_000_000_000} GB`;
const uploadHours = HOSTING_PLAN.uploadSeconds / 3600;

const points: ChapterPoint[] = [
  {
    title: "Keep editing while it uploads",
    body: "Pause and resume the transfer, and reopen the project's link whenever you need it.",
  },
  {
    title: "Easy to watch",
    body: `Adaptive streaming up to ${HOSTING_PLAN.maximumResolution}p, with a searchable transcript and chapters next to the video.`,
  },
  {
    title: "Sign in with an email code",
    body: "No BlitzReels account or password. Revoke a link from the app and it stops working.",
  },
];

function activeIndex<T extends { start: number }>({ items, time }: { items: T[]; time: number }) {
  let index = 0;
  for (const [position, item] of items.entries()) if (item.start <= time) index = position;
  return index;
}

export function ShareChapter() {
  const [tab, setTab] = useState<Tab>("transcript");
  const [time, setTime] = useState(52);
  const cue = activeIndex({ items: CUES, time });
  const chapter = activeIndex({ items: CHAPTERS, time });

  function seek({ start, control }: { start: number; control: Tab }) {
    setTime(start);
    trackJourneyEvent({
      eventName: "landing_demo_changed",
      area: "landing",
      payload: { demo: "share", control, value: start },
    });
  }

  return (
    <Section id="share" className="scroll-mt-24 py-16 sm:py-20">
      <JourneySectionView area="landing" section="share" payload={{ page: "home" }} />
      <ChapterHeader
        mark={chapters.share}
        title="Share a link, not a file."
        lede="Upload the edit from the sidebar next to the editor and send one link. Viewers can search what was said and skip to the part they need."
        aside={
          <p className="text-sm leading-6 text-faint">
            Optional hosting: {price} a month plus tax, with {storage} of storage and {uploadHours} hours of
            uploads every {HOSTING_PLAN.uploadWindowDays} days. The app and local exports stay free.
          </p>
        }
      />

      <div data-reveal className="panel app-surface mt-10 grid overflow-hidden rounded-card sm:mt-14 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div className="flex flex-col justify-center gap-4 bg-background p-4 sm:p-6">
          <div className="relative aspect-video overflow-hidden rounded-inner bg-black shadow-[0_0_0_1px_rgb(255_255_255/18%)]">
            <Image
              src={assets.screenTake}
              alt="A shared recording of a product walkthrough"
              fill
              sizes="(min-width: 1024px) 720px, 90vw"
              className="object-cover object-[30%_40%]"
            />
            <div className="absolute right-[3%] bottom-[5%] aspect-square w-[20%] overflow-hidden rounded-tile shadow-[0_10px_24px_-8px_rgb(0_0_0/80%)]">
              <Image
                src={assets.cameraTake}
                alt=""
                fill
                sizes="160px"
                className="object-cover object-[52%_35%]"
              />
            </div>
          </div>
          <div>
            <div className="relative h-1 rounded-full bg-fill-control">
              <div
                className="absolute inset-y-0 left-0 rounded-full bg-primary transition-[width] duration-500 ease-out-expo"
                style={{ width: `${(time / DURATION) * 100}%` }}
              />
              {CHAPTERS.filter((item) => item.start > 0).map((item) => (
                <span
                  key={item.start}
                  aria-hidden
                  className="absolute -top-0.5 h-2 w-0.5 rounded-full bg-foreground/70"
                  style={{ left: `${(item.start / DURATION) * 100}%` }}
                />
              ))}
            </div>
            <div className="mt-3 flex items-center justify-between gap-4 text-[13px]">
              <span className="truncate text-muted-foreground">
                {chapter + 1} / {CHAPTERS.length} · {CHAPTERS[chapter].title}
              </span>
              <span className="shrink-0 font-mono text-faint tabular-nums">
                {formatTime(time)} / {formatTime(DURATION)}
              </span>
            </div>
          </div>
        </div>

        <div className="flex min-h-[380px] flex-col gap-4 p-5 sm:p-6">
          <div className="flex items-center justify-between gap-3 rounded-inner bg-fill-control px-3 py-2">
            <span className="truncate font-mono text-[13px] text-foreground">blitzrecorder.com/s/k3Hq9vTx2LmP</span>
            <span className="label-mono shrink-0 text-primary">Live</span>
          </div>

          <div role="tablist" aria-label="Video notes" className="grid grid-cols-2 gap-0.5 rounded-control bg-fill-control p-0.5">
            {(["transcript", "chapters"] as const).map((value) => (
              <button
                key={value}
                type="button"
                role="tab"
                aria-selected={tab === value}
                onClick={() => setTab(value)}
                className={cn(
                  "h-[30px] rounded-inner text-[13px] font-medium capitalize transition-colors",
                  tab === value ? "bg-fill-selected text-foreground" : "text-faint hover:text-foreground",
                )}
              >
                {value}
              </button>
            ))}
          </div>

          <ol role="tabpanel" className="flex flex-col gap-1">
            {tab === "transcript"
              ? CUES.map((item, index) => (
                  <li key={item.start}>
                    <button
                      type="button"
                      aria-current={index === cue ? "true" : undefined}
                      onClick={() => seek({ start: item.start, control: "transcript" })}
                      className={cn(
                        "grid w-full grid-cols-[44px_1fr] gap-2 rounded-inner px-2 py-2 text-left text-[13px] leading-5 transition-colors",
                        index === cue ? "bg-fill-selected" : "hover:bg-fill-hover",
                      )}
                    >
                      <span className="font-mono text-faint tabular-nums">{formatTime(item.start)}</span>
                      <span>
                        <span className="block text-xs text-primary/80">{item.speaker}</span>
                        <span className={index === cue ? "text-foreground" : "text-muted-foreground"}>{item.text}</span>
                      </span>
                    </button>
                  </li>
                ))
              : CHAPTERS.map((item, index) => (
                  <li key={item.start}>
                    <button
                      type="button"
                      aria-current={index === chapter ? "true" : undefined}
                      onClick={() => seek({ start: item.start, control: "chapters" })}
                      className={cn(
                        "grid w-full grid-cols-[44px_1fr] gap-2 rounded-inner px-2 py-2.5 text-left text-[13px] transition-colors",
                        index === chapter ? "bg-fill-selected text-foreground" : "text-muted-foreground hover:bg-fill-hover",
                      )}
                    >
                      <span className="font-mono text-faint tabular-nums">{formatTime(item.start)}</span>
                      <span className="font-medium">{item.title}</span>
                    </button>
                  </li>
                ))}
          </ol>
        </div>
      </div>

      <ChapterPoints points={points} />
    </Section>
  );
}

"use client";

import Image from "next/image";
import { useState, type CSSProperties } from "react";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterHeader, ChapterPoints, chapters, type ChapterPoint } from "@/components/site/landing/chapter";
import { trackJourneyEvent } from "@/lib/journey-events";
import { assets } from "@/lib/assets";
import { cn } from "@/lib/utils";

type Aspect = "9:16" | "16:9";
type Layout = "split" | "pip" | "screen" | "camera";
type Box = { top: number; left: number; width: number; height: number; opacity: number; radius: number };

const layouts: { key: Layout; label: string }[] = [
  { key: "split", label: "Split" },
  { key: "pip", label: "Picture in picture" },
  { key: "screen", label: "Screen only" },
  { key: "camera", label: "Camera only" },
];

const full: Box = { top: 0, left: 0, width: 100, height: 100, opacity: 1, radius: 0 };

function geometry({ aspect, layout }: { aspect: Aspect; layout: Layout }): { screen: Box; camera: Box } {
  const tall = aspect === "9:16";
  switch (layout) {
    case "split":
      return tall
        ? {
            screen: { top: 0, left: 0, width: 100, height: 50, opacity: 1, radius: 0 },
            camera: { top: 50, left: 0, width: 100, height: 50, opacity: 1, radius: 0 },
          }
        : {
            screen: { top: 0, left: 0, width: 58, height: 100, opacity: 1, radius: 0 },
            camera: { top: 0, left: 58, width: 42, height: 100, opacity: 1, radius: 0 },
          };
    case "pip":
      return tall
        ? {
            screen: full,
            camera: { top: 70, left: 52, width: 42, height: 24, opacity: 1, radius: 14 },
          }
        : {
            screen: full,
            camera: { top: 66, left: 74, width: 23, height: 28, opacity: 1, radius: 12 },
          };
    case "screen":
      return {
        screen: full,
        camera: { top: 80, left: 80, width: 0, height: 0, opacity: 0, radius: 12 },
      };
    case "camera":
      return {
        screen: { top: 0, left: 0, width: 100, height: 100, opacity: 0, radius: 0 },
        camera: full,
      };
  }
}

function boxStyle(box: Box): CSSProperties {
  return {
    top: `${box.top}%`,
    left: `${box.left}%`,
    width: `${box.width}%`,
    height: `${box.height}%`,
    opacity: box.opacity,
    borderRadius: box.radius,
  };
}

const points: ChapterPoint[] = [
  {
    title: "Every source in one take",
    body: "A screen, window, or app, plus a camera, your microphone, and Mac audio.",
  },
  {
    title: "Switch scenes while you talk",
    body: "Move from a split to your camera alone mid-sentence. Nothing to redo later.",
  },
  {
    title: "Backgrounds and crops",
    body: "Padding, corners, and backgrounds are set before the take, not after.",
  },
];

export function RecordChapter() {
  const [aspect, setAspect] = useState<Aspect>("9:16");
  const [layout, setLayout] = useState<Layout>("split");
  const boxes = geometry({ aspect, layout });

  function track({ control, value }: { control: string; value: string }) {
    trackJourneyEvent({
      eventName: "landing_demo_changed",
      area: "landing",
      payload: { demo: "composer", control, value },
    });
  }

  return (
    <Section id="record" className="scroll-mt-24 pt-24 pb-16 sm:pt-32 sm:pb-20">
      <JourneySectionView area="landing" section="record" payload={{ page: "home" }} />
      <ChapterHeader
        mark={chapters.record}
        title="Frame the shot first."
        lede="Pick 9:16 or 16:9 and a layout before you press record. The preview is the export."
        aside={null}
      />

      <div data-reveal className="panel app-surface mt-10 grid overflow-hidden rounded-card sm:mt-14 lg:grid-cols-[minmax(0,1fr)_300px]">
        <div className="relative grid min-h-[440px] place-items-center bg-background px-4 pt-14 pb-10 sm:min-h-[560px]">
          <div
            className={cn(
              "relative overflow-hidden rounded-inner bg-black shadow-[0_0_0_1px_rgb(255_255_255/30%)] transition-[width,aspect-ratio] duration-700 ease-out-expo",
              aspect === "9:16"
                ? "aspect-[9/16] w-[min(240px,62vw)] sm:w-[270px]"
                : "aspect-video w-[min(640px,100%)]",
            )}
          >
            <div
              className="absolute overflow-hidden transition-all duration-700 ease-out-expo"
              style={boxStyle(boxes.screen)}
            >
              <Image
                src={assets.screenTake}
                alt="Screen source: a Codex window"
                fill
                sizes="(min-width: 1024px) 640px, 90vw"
                className="object-cover object-[30%_40%]"
              />
            </div>
            <div
              className="absolute overflow-hidden transition-all duration-700 ease-out-expo"
              style={{ ...boxStyle(boxes.camera), boxShadow: layout === "pip" ? "0 10px 24px -8px rgb(0 0 0 / 80%)" : "none" }}
            >
              <Image
                src={assets.cameraTake}
                alt="Camera source: the presenter at their desk"
                fill
                sizes="(min-width: 1024px) 640px, 90vw"
                className="object-cover object-[52%_35%]"
              />
            </div>
          </div>
          <span className="label-mono absolute top-4 left-4 flex items-center gap-2 text-muted-foreground">
            <span className="size-2 rounded-full bg-record [animation:br-rec_1.6s_ease-in-out_infinite]" />
            Live preview
          </span>
          <span className="label-mono absolute top-4 right-4 text-faint">{aspect}</span>
        </div>

        <div className="flex flex-col gap-6 p-5 sm:p-6">
          <fieldset>
            <legend className="label-mono text-faint">Frame</legend>
            <div className="mt-3 grid grid-cols-2 gap-0.5 rounded-control bg-fill-control p-0.5">
              {(["9:16", "16:9"] as const).map((value) => (
                <button
                  key={value}
                  type="button"
                  aria-pressed={aspect === value}
                  onClick={() => {
                    setAspect(value);
                    track({ control: "aspect", value });
                  }}
                  className={cn(
                    "h-[30px] rounded-inner font-mono text-[13px] transition-colors",
                    aspect === value ? "bg-fill-selected text-foreground" : "text-faint hover:text-foreground",
                  )}
                >
                  {value}
                </button>
              ))}
            </div>
          </fieldset>

          <fieldset>
            <legend className="label-mono text-faint">Composition</legend>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {layouts.map((item) => (
                <button
                  key={item.key}
                  type="button"
                  aria-pressed={layout === item.key}
                  onClick={() => {
                    setLayout(item.key);
                    track({ control: "layout", value: item.key });
                  }}
                  className={cn(
                    "flex flex-col items-center gap-2.5 rounded-tile px-2 pt-3.5 pb-3 text-xs font-medium transition-colors",
                    layout === item.key
                      ? "bg-fill-selected text-foreground"
                      : "bg-fill-quiet text-faint hover:bg-fill-hover hover:text-foreground",
                  )}
                >
                  <LayoutGlyph layout={item.key} active={layout === item.key} />
                  {item.label}
                </button>
              ))}
            </div>
          </fieldset>

          <p className="mt-auto text-sm leading-6 text-faint">
            Try it. These are the same four compositions as the app, with frames from a real take.
          </p>
        </div>
      </div>

      <ChapterPoints points={points} />
    </Section>
  );
}

function LayoutGlyph({ layout, active }: { layout: Layout; active: boolean }) {
  const stroke = active ? "var(--primary)" : "currentColor";
  return (
    <svg viewBox="0 0 20 32" className="h-8 w-5" fill="none" aria-hidden>
      <rect x="0.75" y="0.75" width="18.5" height="30.5" rx="2.5" stroke={stroke} strokeWidth="1.5" opacity="0.9" />
      {layout === "split" && (
        <>
          <rect x="3" y="3" width="14" height="12" rx="1" fill={stroke} opacity="0.35" />
          <rect x="3" y="17" width="14" height="12" rx="1" fill={stroke} opacity="0.7" />
        </>
      )}
      {layout === "pip" && (
        <>
          <rect x="3" y="3" width="14" height="26" rx="1" fill={stroke} opacity="0.35" />
          <rect x="10" y="21" width="6" height="6" rx="1" fill={stroke} opacity="0.9" />
        </>
      )}
      {layout === "screen" && <rect x="3" y="3" width="14" height="26" rx="1" fill={stroke} opacity="0.35" />}
      {layout === "camera" && <rect x="3" y="3" width="14" height="26" rx="1" fill={stroke} opacity="0.7" />}
    </svg>
  );
}

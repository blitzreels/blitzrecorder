import type { ReactNode } from "react";
import { Heading, Paragraph } from "@/components/ui/typography";
import { cn } from "@/lib/utils";

export type ChapterMark = {
  time: string;
  name: string;
};

export const chapters = {
  record: { time: "00:00", name: "Record" },
  camera: { time: "00:21", name: "iPhone camera" },
  edit: { time: "00:48", name: "Edit" },
  export: { time: "01:12", name: "Export" },
} satisfies Record<string, ChapterMark>;

export function ChapterRuler({ mark }: { mark: ChapterMark }) {
  return (
    <div data-reveal className="relative">
      <div className="flex items-baseline gap-3 pb-3">
        <span className="label-mono text-primary">{mark.time}</span>
        <span className="label-mono text-muted-foreground">{mark.name}</span>
      </div>
      <div className="ruler relative h-3 w-full">
        <div className="segment-bar absolute inset-x-0 -bottom-px h-[3px] rounded-full bg-primary" />
      </div>
    </div>
  );
}

export function ChapterHeader({
  mark,
  title,
  lede,
  aside,
}: {
  mark: ChapterMark;
  title: ReactNode;
  lede: ReactNode;
  aside: ReactNode | null;
}) {
  return (
    <div>
      <ChapterRuler mark={mark} />
      <div className="mt-8 grid gap-5 lg:mt-12 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)] lg:items-end lg:gap-16">
        <Heading level={2} data-reveal className="max-w-[17ch]">
          {title}
        </Heading>
        <div data-reveal className={cn("max-w-md", aside ? "flex flex-col gap-5" : "")}>
          <Paragraph>{lede}</Paragraph>
          {aside}
        </div>
      </div>
    </div>
  );
}

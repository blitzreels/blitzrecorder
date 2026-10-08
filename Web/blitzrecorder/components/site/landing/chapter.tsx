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
  share: { time: "01:34", name: "Share" },
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

/** Timestamp chip for centered headers, where a full-width ruler would split the page into identical bands. */
function ChapterChip({ mark }: { mark: ChapterMark }) {
  return (
    <span data-reveal className="inline-flex items-center gap-2.5 rounded-full bg-fill-control px-3 py-1.5">
      <span className="label-mono text-primary">{mark.time}</span>
      <span className="size-1 rounded-full bg-faint" aria-hidden />
      <span className="label-mono text-muted-foreground">{mark.name}</span>
    </span>
  );
}

export type ChapterAlign = "split" | "center" | "stack";

export function ChapterHeader({
  mark,
  title,
  lede,
  aside,
  align,
}: {
  mark: ChapterMark;
  title: ReactNode;
  lede: ReactNode;
  aside: ReactNode | null;
  align: ChapterAlign;
}) {
  if (align === "center") {
    return (
      <div className="flex flex-col items-center text-center">
        <ChapterChip mark={mark} />
        <Heading level={2} data-reveal className="mt-6 max-w-[20ch] text-balance">
          {title}
        </Heading>
        <div data-reveal className="mt-5 flex max-w-xl flex-col items-center gap-4">
          <Paragraph className="text-pretty">{lede}</Paragraph>
          {aside}
        </div>
      </div>
    );
  }
  if (align === "stack") {
    return (
      <div>
        <ChapterChip mark={mark} />
        <Heading level={2} data-reveal className="mt-6 max-w-[14ch]">
          {title}
        </Heading>
        <div data-reveal className="mt-5 flex max-w-md flex-col gap-5">
          <Paragraph className="text-pretty">{lede}</Paragraph>
          {aside}
        </div>
      </div>
    );
  }
  return (
    <div>
      <ChapterRuler mark={mark} />
      <div className="mt-8 grid gap-5 lg:mt-12 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)] lg:items-end lg:gap-16">
        <Heading level={2} data-reveal className="max-w-[17ch]">
          {title}
        </Heading>
        <div data-reveal className={cn("max-w-md", aside ? "flex flex-col gap-5" : "")}>
          <Paragraph className="text-pretty">{lede}</Paragraph>
          {aside}
        </div>
      </div>
    </div>
  );
}

export type ChapterPoint = { title: string; body: string };

/** `columns` sits under a wide demo; `numbered` reads as steps; `list` stacks inside a narrow text column. */
export function ChapterPoints({ points, layout }: { points: ChapterPoint[]; layout: "columns" | "numbered" | "list" }) {
  if (layout === "list") {
    return (
      <ul className="mt-10 flex flex-col gap-6">
        {points.map((point) => (
          <li key={point.title} data-reveal className="grid grid-cols-[20px_minmax(0,1fr)] gap-3">
            <span className="mt-2 size-2 rounded-full bg-primary" aria-hidden />
            <div>
              <h3 className="font-display text-lg font-bold tracking-[-0.01em]">{point.title}</h3>
              <p className="mt-1.5 text-[15px] leading-6 text-pretty text-muted-foreground">{point.body}</p>
            </div>
          </li>
        ))}
      </ul>
    );
  }
  return (
    <ol className={cn("mt-12 grid gap-8 sm:grid-cols-3", layout === "numbered" && "sm:gap-6")}>
      {points.map((point, index) => (
        <li
          key={point.title}
          data-reveal
          className={layout === "numbered" ? "rounded-card bg-fill-card p-5 sm:p-6" : "border-t border-separator pt-5"}
        >
          {layout === "numbered" && (
            <span className="label-mono text-primary">{String(index + 1).padStart(2, "0")}</span>
          )}
          <h3 className={cn("font-display text-lg font-bold tracking-[-0.01em]", layout === "numbered" && "mt-3")}>
            {point.title}
          </h3>
          <p className="mt-2 text-[15px] leading-6 text-pretty text-muted-foreground">{point.body}</p>
        </li>
      ))}
    </ol>
  );
}

/** Full-bleed tinted band so alternate chapters read as their own room. */
export function ChapterBand({ children }: { children: ReactNode }) {
  return <div className="border-y border-separator bg-fill-card">{children}</div>;
}

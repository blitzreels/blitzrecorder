import type { ReactNode } from "react";
import { FrameMarks } from "@/components/site/landing/frame";
import { cn } from "@/lib/utils";

/**
 * The one screen for "something isn't here" and "something broke": a big mark in an empty viewfinder,
 * a plain sentence, and the next step. `fill` centers it in the viewport; inline sits inside the app shell.
 */
export function Problem({ mark, title, children, actions, footer, fill }: {
  mark: string;
  title: string;
  children: ReactNode;
  actions: ReactNode;
  footer: ReactNode | null;
  fill: boolean;
}) {
  return <section className={cn("mx-auto flex w-full max-w-xl flex-col items-center px-4 text-center",
    fill ? "min-h-[calc(100svh-56px)] justify-center pb-[10vh]" : "py-20")}>
    <div className="relative px-10 py-6 sm:px-14 sm:py-8">
      <FrameMarks className="inset-0 opacity-40" />
      <p aria-hidden className="type-hero text-[clamp(4rem,12vw,7rem)] text-white/[0.14] tabular-nums">{mark}</p>
    </div>
    <h1 className="type-title mt-10 text-[clamp(1.875rem,4vw,2.5rem)]">{title}</h1>
    <div className="mt-4 max-w-[44ch] text-[15px] leading-6 text-pretty text-muted-foreground">{children}</div>
    <div className="mt-8 flex flex-wrap items-center justify-center gap-2">{actions}</div>
    {footer ? <p className="mt-8 text-[12px] text-faint">{footer}</p> : null}
  </section>;
}

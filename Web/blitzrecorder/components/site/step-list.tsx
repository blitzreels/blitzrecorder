import type { ProductScreen } from "@/lib/content";
import { cn } from "@/lib/utils";

/** Numbered steps in a row: how a visitor gets from nothing to a finished video. */
export function StepList({ steps }: { steps: ProductScreen[] }) {
  return (
    <ol className={cn("grid gap-10 sm:grid-cols-2", steps.length === 3 ? "lg:grid-cols-3" : "lg:grid-cols-4")}>
      {steps.map((step, index) => (
        <li key={step.title}>
          <span className="grid size-8 place-items-center rounded-full bg-fill-control text-sm font-semibold tabular-nums">
            {index + 1}
          </span>
          <h3 className="mt-5 text-[17px] font-semibold tracking-[-0.01em]">{step.title}</h3>
          <p className="mt-2 text-[15px] leading-6 text-muted-foreground">{step.text}</p>
        </li>
      ))}
    </ol>
  );
}

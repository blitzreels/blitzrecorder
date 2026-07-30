import type { ReactNode } from "react";

export function Eyebrow({
  children,
  center,
}: {
  children: ReactNode;
  center?: boolean;
}) {
  return (
    <span
      className={
        "inline-flex items-center gap-2.5 text-sm font-semibold uppercase tracking-[0.2em] text-primary" +
        (center ? " justify-center" : "")
      }
    >
      <span className="h-px w-7 bg-gradient-to-r from-transparent to-primary/70" />
      {children}
    </span>
  );
}

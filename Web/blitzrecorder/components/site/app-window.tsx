import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export function AppWindow({
  children,
  className,
}: {
  children: ReactNode;
  className: string;
}) {
  return (
    <div
      className={cn(
        "app-surface relative overflow-hidden rounded-card bg-[#262425]",
        className,
      )}
    >
      <div aria-hidden className="absolute top-[1.1%] left-[1%] z-10 flex gap-1.5 max-sm:hidden">
        {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
          <span key={color} className="size-[max(6px,min(0.7vw,10px))] rounded-full" style={{ background: color }} />
        ))}
      </div>
      {children}
    </div>
  );
}

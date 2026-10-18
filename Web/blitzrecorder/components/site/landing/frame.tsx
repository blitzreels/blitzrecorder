import { cn } from "@/lib/utils";

const corners = [
  "top-0 left-0 border-t-2 border-l-2 rounded-tl-[6px]",
  "top-0 right-0 border-t-2 border-r-2 rounded-tr-[6px]",
  "bottom-0 left-0 border-b-2 border-l-2 rounded-bl-[6px]",
  "bottom-0 right-0 border-b-2 border-r-2 rounded-br-[6px]",
];

/** Viewfinder corner marks: the page's way of saying "this is what the camera sees". */
export function FrameMarks({ className }: { className: string }) {
  return (
    <span aria-hidden className={cn("pointer-events-none absolute", className)}>
      {corners.map((corner) => (
        <span key={corner} className={cn("absolute size-5 border-white/80 sm:size-7", corner)} />
      ))}
    </span>
  );
}

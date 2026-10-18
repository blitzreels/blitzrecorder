import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * MacBook Pro drawn in CSS: black bezel with the notch, then the aluminium base with its thumb groove.
 * `children` fills the screen, which is 16:10 like the real display.
 */
export function MacBook({ children, className }: { children: ReactNode; className: string }) {
  return <div className={cn("relative", className)}>
    <div className="relative rounded-[3.2%/5%] bg-[#0b0b0c] p-[1.6%] pb-[2.4%] shadow-[0_0_0_1px_rgb(255_255_255/9%),0_60px_120px_-40px_rgb(0_0_0/90%)]">
      <div className="relative aspect-[16/10] overflow-hidden rounded-[0.6%/1%] bg-black">
        {children}
        <span aria-hidden className="absolute top-0 left-1/2 h-[3.2%] w-[11%] -translate-x-1/2 rounded-b-[6px] bg-[#0b0b0c]" />
      </div>
    </div>
    <div aria-hidden className="relative -mx-[6.5%] h-[clamp(10px,1.6vw,20px)] rounded-b-[40%_100%] bg-[linear-gradient(to_bottom,#3a3a3e,#1c1c1f_55%,#0f0f11)] shadow-[0_1px_0_rgb(255_255_255/12%)_inset,0_30px_60px_-20px_rgb(0_0_0/80%)]">
      <span className="absolute top-0 left-1/2 h-[45%] w-[15%] -translate-x-1/2 rounded-b-[10px] bg-[#141416] shadow-[inset_0_1px_2px_rgb(0_0_0/60%)]" />
    </div>
  </div>;
}

/** iPhone with a titanium edge and the Dynamic Island. `children` fills the 9:19.5 screen. */
export function IPhone({ children, className }: { children: ReactNode; className: string }) {
  return <div className={cn("relative shrink-0", className)}>
    <div className="relative rounded-[18%/8.3%] bg-[linear-gradient(145deg,#5a5a60,#2a2a2e_40%,#45454b)] p-[1.6%] shadow-[0_40px_80px_-30px_rgb(0_0_0/90%)]">
      <div className="relative rounded-[16.5%/7.6%] bg-black p-[2.6%]">
        <div className="relative aspect-[9/19.5] overflow-hidden rounded-[13.5%/6.2%] bg-black">
          {children}
          <span aria-hidden className="absolute top-[1.6%] left-1/2 h-[3.6%] w-[31%] -translate-x-1/2 rounded-full bg-black" />
        </div>
      </div>
    </div>
  </div>;
}

/** A silent looping clip that only plays while on screen (`useLoopingVideo` drives it). */
export function ScreenVideo({ src, poster, label, className }: { src: string; poster: string; label: string; className: string }) {
  return <video data-loop-video src={src} poster={poster} muted loop playsInline preload="none" aria-label={label}
    className={cn("absolute inset-0 size-full object-cover", className)} />;
}

import Image from "next/image";
import { MacBook, ScreenVideo } from "@/components/site/devices";
import { assets, realVideos } from "@/lib/assets";
import { cn } from "@/lib/utils";

/**
 * Where the editor render's preview canvas sits, measured on the 2880x1800 proof render
 * (`Scripts/ui-proof.sh editor:export`, height 900, scale 2). The real export plays in that rectangle.
 */
const CANVAS = { left: "8.75%", top: "7.8889%", width: "52.7778%", height: "47.4444%" };

/** The real BlitzRecorder editor on a MacBook, playing the export of the same take. */
export function StudioMockup({ className, priority }: { className: string; priority: boolean }) {
  return <div className={cn("relative", className)}>
    <MacBook className="w-full">
      <Image src={assets.editorExport} alt="The BlitzRecorder editor exporting a take in 4K, with its scenes and zooms on the timeline"
        fill priority={priority} sizes="(min-width: 1180px) 1120px, (min-width: 640px) 95vw, 160vw" className="object-cover" />
      <div className="absolute overflow-hidden rounded-[0.4vw] bg-black" style={CANVAS}>
        <ScreenVideo src={realVideos.landscape.src} poster={realVideos.landscape.poster}
          label="A video exported from BlitzRecorder: the presenter on the left, his screen on the right" className="" />
      </div>
    </MacBook>
  </div>;
}

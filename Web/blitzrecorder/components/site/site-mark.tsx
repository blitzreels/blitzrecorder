import Image from "next/image";
import Link from "next/link";
import { assets } from "@/lib/assets";
import { cn } from "@/lib/utils";

/** App icon plus wordmark. The icon stays when the bar is narrow. */
export const SiteMark = ({ compact = false }: { compact?: boolean }) => <Link href="/" className="flex shrink-0 items-center gap-2.5">
  <Image src={assets.macIcon} width={22} height={22} alt="" className="size-[22px] rounded-[22.5%]" />
  <span className={cn(
    "text-[15px] font-semibold tracking-[-0.02em]",
    compact ? "hidden sm:inline" : "hidden min-[380px]:inline",
  )}>BlitzRecorder</span>
</Link>;

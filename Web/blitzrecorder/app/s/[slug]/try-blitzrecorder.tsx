"use client";

import Image from "next/image";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DownloadButton } from "@/components/site/download-button";
import { useUserOS } from "@/components/site/use-user-os";
import icon from "../../icon.png";
import { TRY_URL } from "./try-url";

export function TryBlitzRecorderCard() {
  const os = useUserOS();
  return <aside className="product-surface mt-5 flex flex-col gap-5 rounded-[16px] p-5 sm:p-6 md:flex-row md:items-center md:gap-8"
    aria-label="Try BlitzRecorder">
    <div className="flex min-w-0 flex-1 items-start gap-4">
      <Image src={icon} alt="" width={48} height={48} className="size-10 shrink-0 rounded-tile sm:size-12" />
      <div className="min-w-0">
        <h2 className="text-[17px] leading-snug font-semibold tracking-[-0.01em] text-balance">
          Made with BlitzRecorder, free for Mac.
        </h2>
        <p className="mt-1 max-w-[56ch] text-[14px] leading-6 text-pretty text-muted-foreground">
          Record your screen and your face in one take, then share a link like this one.
        </p>
      </div>
    </div>
    <div className="flex shrink-0 flex-col items-stretch gap-2 sm:flex-row sm:items-center md:flex-col md:items-stretch">
      {os === "mac"
        ? <DownloadButton size="lg" label="Download free for Mac" source="share_page_card" className="" />
        : <Button size="lg" render={<Link href={TRY_URL} />}>Get BlitzRecorder<ArrowRight /></Button>}
      {os === "mac" && <Link href={TRY_URL} className="inline-flex h-9 items-center justify-center gap-1 rounded-control px-3 text-[13px] text-muted-foreground transition-colors hover:bg-fill-quiet hover:text-foreground">
        See how it works<ArrowRight className="size-3.5" />
      </Link>}
    </div>
  </aside>;
}

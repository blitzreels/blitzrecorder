"use client";

import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DownloadButton } from "@/components/site/download-button";
import { useUserOS } from "@/components/site/use-user-os";
import { freeIncludes } from "@/lib/content";
import icon from "../../icon.png";
import { TRY_URL } from "./try-url";

export function TryBlitzRecorderCard() {
  const os = useUserOS();
  return <aside className="mt-5 flex flex-col gap-5 rounded-card bg-card p-5 sm:p-6 md:flex-row md:items-center md:gap-8"
    aria-label="Try BlitzRecorder">
    <div className="flex min-w-0 flex-1 items-start gap-4">
      <Image src={icon} alt="" width={48} height={48} className="size-10 shrink-0 rounded-tile sm:size-12" />
      <div className="min-w-0">
        <h2 className="font-display text-lg leading-snug font-bold tracking-tight text-balance">
          This video was made with BlitzRecorder. It&apos;s free.
        </h2>
        <p className="mt-1 max-w-[56ch] text-sm leading-6 text-pretty text-muted-foreground">
          Record your screen and camera together on a Mac, then send a link like this one.
        </p>
        <ul className="mt-3 grid gap-x-5 gap-y-1.5 text-[13px] text-muted-foreground sm:grid-cols-2" aria-label="Included for free">
          {freeIncludes.slice(0, 4).map((item) => <li key={item} className="flex items-center gap-2">
            <Check className="size-3.5 shrink-0 text-primary" strokeWidth={2.5} />{item}
          </li>)}
        </ul>
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

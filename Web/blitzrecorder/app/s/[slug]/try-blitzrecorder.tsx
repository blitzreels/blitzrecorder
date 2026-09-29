"use client";

import Image from "next/image";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DownloadButton } from "@/components/site/download-button";
import { useUserOS } from "@/components/site/use-user-os";
import { freeIncludes } from "@/lib/content";
import icon from "../../icon.png";
import { TRY_URL } from "./try-url";

export function TryBlitzRecorderCard() {
  const os = useUserOS();
  return <aside className="mt-4 flex flex-col gap-5 rounded-card bg-card p-5 sm:flex-row sm:items-center sm:gap-6 sm:p-6"
    aria-label="Try BlitzRecorder">
    <Image src={icon} alt="" width={56} height={56} className="size-14 shrink-0 rounded-tile" />
    <div className="min-w-0 flex-1">
      <p className="text-[13px] text-faint">Made with BlitzRecorder</p>
      <h2 className="mt-1 font-display text-lg font-bold tracking-tight text-balance">Record videos like this one, free.</h2>
      <p className="mt-1.5 max-w-[60ch] text-sm leading-6 text-muted-foreground">
        Screen and camera in one take, silence cuts, on-device transcripts, and a share link with chapters.
      </p>
      <ul className="mt-3 flex flex-wrap gap-1.5" aria-label="Included for free">
        {freeIncludes.slice(0, 4).map((item) => <li key={item}
          className="rounded-control bg-fill-quiet px-2 py-1 text-xs text-muted-foreground">{item}</li>)}
      </ul>
    </div>
    <div className="flex shrink-0 flex-wrap gap-2 sm:flex-col sm:items-stretch">
      {os === "mac"
        ? <DownloadButton size="lg" label="Download free for Mac" source="share_page_card" className="" />
        : <Button size="lg" render={<Link href={TRY_URL} />}>Try BlitzRecorder free<ArrowRight /></Button>}
      {os === "mac" && <Button variant="ghost" render={<Link href={TRY_URL} />}>See what it does</Button>}
    </div>
  </aside>;
}

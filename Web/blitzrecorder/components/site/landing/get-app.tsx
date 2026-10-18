"use client";

import { DownloadButton } from "@/components/site/download-button";
import { NotifyForm } from "@/components/site/notify-form";
import { useUserOS } from "@/components/site/use-user-os";
import { macCompatibility } from "@/lib/content";
import { cn } from "@/lib/utils";

/**
 * The page's one action. Macs download the app; phones and PCs, which can't run it,
 * get the link by email instead of a DMG they can't open.
 */
export function GetApp({ source, align }: { source: string; align: "center" | "start" }) {
  const os = useUserOS();
  const elsewhere = os !== null && os !== "mac";

  return (
    <div className={cn("flex flex-col gap-4", align === "center" ? "items-center text-center" : "items-start")}>
      {elsewhere ? (
        <NotifyForm
          source={`download_link_${source}_${os}`}
          os={os}
          cta="Email me the Mac link"
          success="Sent. Open the email on your Mac."
        />
      ) : (
        <DownloadButton source={source} size="lg" label="Download free for Mac" className="px-6" />
      )}
      <p className="text-sm text-balance text-faint">
        {elsewhere ? "BlitzRecorder is a Mac app. " : ""}No account · No watermark · {macCompatibility}
      </p>
    </div>
  );
}

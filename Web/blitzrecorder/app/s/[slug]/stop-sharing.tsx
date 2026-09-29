"use client";

import { Popover } from "@base-ui/react/popover";
import { useRouter } from "next/navigation";
import { useActionState, useState, type ReactElement, type ReactNode } from "react";
import { CircleAlert, LoaderCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { stopSharing, type HostingActionResult } from "@/lib/hosting/web-actions";

const UNREACHABLE: HostingActionResult = { ok: false, error: "Can’t reach BlitzRecorder. Check your connection and try again." };

/** Stopping the open video leaves its page, so the library route picks the next video to show. */
const StopSharingForm = ({ slug, current, onDone }: { slug: string; current: boolean; onDone: () => void }) => {
  const router = useRouter();
  const [state, action, pending] = useActionState<HostingActionResult | null>(async () => {
    const result = await stopSharing(slug).catch(() => UNREACHABLE);
    if (!result.ok) return result;
    onDone();
    if (current) router.replace("/hosting/videos");
    else router.refresh();
    return result;
  }, null);
  return <form action={action} className="mt-4 flex flex-col gap-3">
    {state && !state.ok && <p role="alert" className="flex items-start gap-2 text-xs text-pretty text-destructive">
      <CircleAlert className="mt-px size-3.5 shrink-0" /> {state.error}
    </p>}
    <div className="flex justify-end gap-2">
      <Popover.Close render={<Button type="button" variant="ghost" size="sm" disabled={pending} />}>Cancel</Popover.Close>
      <Button type="submit" variant="destructive" size="sm" disabled={pending}>
        {pending ? <><LoaderCircle className="animate-spin" /> Stopping…</> : "Stop sharing"}
      </Button>
    </div>
  </form>;
};

export const StopSharing = ({ slug, title, current, trigger, children }: {
  slug: string; title: string; current: boolean; trigger: ReactElement; children: ReactNode;
}) => {
  const [open, setOpen] = useState(false);
  return <Popover.Root open={open} onOpenChange={setOpen}>
    <Popover.Trigger render={trigger}>{children}</Popover.Trigger>
    <Popover.Portal>
      <Popover.Positioner side="bottom" align="end" sideOffset={6} collisionPadding={12} className="z-[60]">
        <Popover.Popup className={[
          "w-[300px] origin-[var(--transform-origin)] rounded-card bg-popover p-4 text-popover-foreground outline-none",
          "shadow-[0_0_0_1px_var(--border),0_16px_48px_rgb(0_0_0/55%)] transition-[opacity,scale] duration-150",
          "data-[ending-style]:scale-95 data-[ending-style]:opacity-0 data-[starting-style]:scale-95 data-[starting-style]:opacity-0",
        ].join(" ")}>
          <Popover.Title className="text-sm font-semibold">Stop sharing this video?</Popover.Title>
          <Popover.Description className="mt-1.5 text-[13px] leading-relaxed text-pretty text-muted-foreground">
            <span className="text-foreground">{title}</span> will stop playing for anyone with the link. Sharing it
            again from BlitzRecorder creates a new link.
          </Popover.Description>
          <StopSharingForm slug={slug} current={current} onDone={() => setOpen(false)} />
        </Popover.Popup>
      </Popover.Positioner>
    </Popover.Portal>
  </Popover.Root>;
};

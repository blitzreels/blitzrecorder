"use client";

import { Popover } from "@base-ui/react/popover";
import { useState } from "react";
import { Check, Copy, Mail, Share } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatTime } from "@/lib/hosting/details";
import styles from "./player.module.css";

const XLogo = () => <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">
  <path d="M17.75 3h3.07l-6.7 7.66L22 21h-6.17l-4.83-6.32L5.47 21H2.4l7.17-8.2L2 3h6.33l4.37 5.77L17.75 3Zm-1.08 16.18h1.7L7.4 4.74H5.58l11.09 14.44Z" />
</svg>;

const LinkedInLogo = () => <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">
  <path d="M20.45 20.45h-3.56v-5.57c0-1.33-.02-3.04-1.85-3.04-1.86 0-2.14 1.45-2.14 2.94v5.67H9.35V9h3.41v1.56h.05c.48-.9 1.64-1.85 3.37-1.85 3.6 0 4.27 2.37 4.27 5.46v6.28ZM5.34 7.43a2.06 2.06 0 1 1 0-4.13 2.06 2.06 0 0 1 0 4.13ZM7.12 20.45H3.56V9h3.56v11.45ZM22.22 0H1.77C.79 0 0 .77 0 1.73v20.54C0 23.23.79 24 1.77 24h20.45c.98 0 1.78-.77 1.78-1.73V1.73C24 .77 23.2 0 22.22 0Z" />
</svg>;

export function SharePopover({ title, time }: { title: string; time: number }) {
  const [open, setOpen] = useState(false);
  const [atTime, setAtTime] = useState(false);
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  const [base, setBase] = useState("");
  const [canNativeShare, setCanNativeShare] = useState(false);
  const [moment, setMoment] = useState(0);

  const changeOpen = (next: boolean) => {
    if (next) {
      const url = new URL(location.href);
      url.search = "";
      url.hash = "";
      setBase(url.href);
      setMoment(Math.floor(time));
      setCanNativeShare(typeof navigator.share === "function");
    }
    setOpen(next);
  };

  const canStartAt = moment >= 1;
  const link = atTime && canStartAt ? `${base}?t=${moment}` : base;
  const text = `${title} (BlitzRecorder)`;
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true); setFailed(false);
      window.setTimeout(() => setCopied(false), 2000);
    } catch { setFailed(true); }
  };
  const nativeShare = async () => {
    try { await navigator.share({ title, url: link }); setOpen(false); } catch {}
  };
  const targets = [
    { label: "Email", icon: <Mail />, href: `mailto:?subject=${encodeURIComponent(title)}&body=${encodeURIComponent(link)}` },
    { label: "X", icon: <XLogo />, href: `https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(link)}` },
    { label: "LinkedIn", icon: <LinkedInLogo />, href: `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(link)}` },
  ];

  return <Popover.Root open={open} onOpenChange={changeOpen}>
    <Popover.Trigger render={<Button variant="outline" />}><Share />Share</Popover.Trigger>
    <Popover.Portal>
      <Popover.Positioner side="bottom" align="end" sideOffset={8} collisionPadding={12} className="z-[60]">
        <Popover.Popup className={styles.sharePopup}>
          <Popover.Title className="text-sm font-semibold">Share this video</Popover.Title>
          <Popover.Description className="mt-1 text-[13px] text-pretty text-muted-foreground">
            Anyone with the link can watch. No account needed.
          </Popover.Description>
          <div className={styles.shareLink}>
            <input readOnly value={link} aria-label="Video link" onFocus={(event) => event.currentTarget.select()} />
            <Button size="sm" onClick={() => void copy()} aria-live="polite">
              {copied ? <><Check />Copied</> : <><Copy />Copy</>}
            </Button>
          </div>
          {failed && <p role="alert" className="mt-2 text-xs text-muted-foreground">Could not copy. Select the link and copy it.</p>}
          <label className={styles.shareCheck} data-disabled={canStartAt ? undefined : "true"}>
            <input type="checkbox" checked={atTime && canStartAt} disabled={!canStartAt}
              onChange={(event) => setAtTime(event.target.checked)} />
            <span>Start at <span className="tabular-nums">{formatTime(moment)}</span></span>
          </label>
          <div className={styles.shareTargets}>
            {targets.map((target) => <a key={target.label} href={target.href} target="_blank" rel="noopener noreferrer"
              className={styles.shareTarget}>{target.icon}{target.label}</a>)}
            {canNativeShare && <button type="button" className={styles.shareTarget} onClick={() => void nativeShare()}>
              <Share />More
            </button>}
          </div>
        </Popover.Popup>
      </Popover.Positioner>
    </Popover.Portal>
  </Popover.Root>;
}

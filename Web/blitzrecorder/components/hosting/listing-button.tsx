"use client";

import { useRouter } from "next/navigation";
import { useActionState } from "react";
import { Eye, EyeOff, LoaderCircle } from "lucide-react";
import { setListing, type HostingActionResult } from "@/lib/hosting/web-actions";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const UNREACHABLE: HostingActionResult = { ok: false, error: "Can’t reach BlitzRecorder. Check your connection and try again." };

export const ListingButton = ({ slug, listed, title, className, iconOnly = false, redirectOnUnlist }: {
  slug: string; listed: boolean; title: string; className?: string; iconOnly?: boolean; redirectOnUnlist?: string;
}) => {
  const router = useRouter();
  const [state, action, pending] = useActionState<HostingActionResult | null>(async () => {
    const result = await setListing({ slug, listed: !listed }).catch(() => UNREACHABLE);
    if (result.ok && listed && redirectOnUnlist) router.push(redirectOnUnlist);
    else if (result.ok) router.refresh();
    return result;
  }, null);
  const label = listed ? `Unlist ${title}` : `List ${title}`;
  const failed = state && !state.ok ? state.error : null;
  return <form action={action} className="contents">
    <button type="submit" disabled={pending} aria-label={label}
      title={failed ?? (listed ? "Unlist" : "List")}
      className={className ?? cn(buttonVariants({ variant: "ghost", size: "sm" }))}>
      {pending ? <LoaderCircle className="animate-spin" size={14} /> : listed ? <EyeOff size={14} /> : <Eye size={14} />}
      {!iconOnly && <span>{listed ? "Unlist" : "List"}</span>}
    </button>
    {!iconOnly && failed && <p role="alert" className="basis-full text-xs text-record">{failed}</p>}
    {iconOnly && failed && <span role="alert" className="sr-only">{failed}</span>}
  </form>;
};

"use client";

import { useRouter } from "next/navigation";
import { useActionState, type ReactNode } from "react";
import { LogOut } from "lucide-react";
import { signOut, type HostingActionResult } from "@/lib/hosting/web-actions";

const FAILED = "Couldn’t sign out. Check your connection and try again.";

const useSignOut = (scope: "device" | "everywhere") => {
  const router = useRouter();
  return useActionState<HostingActionResult | null>(async () => {
    const result = await signOut(scope).catch((): HostingActionResult => ({ ok: false, error: FAILED }));
    if (result.ok) router.refresh();
    return result;
  }, null);
};

export const SignOutButton = ({ scope = "device", className, children }: {
  scope?: "device" | "everywhere"; className?: string; children?: ReactNode;
}) => {
  const [state, action, pending] = useSignOut(scope);
  const failed = state && !state.ok ? state.error : null;
  return <form action={action} className="contents">
    <button type="submit" disabled={pending} title={failed ?? undefined} className={className ?? [
      "inline-flex h-7 flex-none items-center gap-1.5 rounded-control px-2 text-xs font-medium text-muted-foreground",
      "transition-colors hover:bg-fill-hover hover:text-foreground disabled:opacity-60",
    ].join(" ")}>
      {scope === "device" && <LogOut className="size-3.5" aria-hidden />}
      {pending ? "Signing out…" : failed ? "Retry sign out" : children ?? "Sign out"}
    </button>
    {failed && <span role="alert" className="sr-only">{failed}</span>}
  </form>;
};

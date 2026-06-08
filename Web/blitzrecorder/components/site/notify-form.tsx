"use client";

import { useState, type FormEvent } from "react";
import { ArrowUpRight, Check } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { trackJourneyEvent } from "@/lib/journey-events";

/**
 * Lightweight email capture so visitors who can't act now (not on a Mac, or
 * waiting for the iPhone app) leave a way to reach them instead of bouncing.
 * Posts to /api/notify and reports success even when the store is unconfigured.
 */
export function NotifyForm({
  source,
  os,
  cta = "Notify me",
  placeholder = "you@email.com",
  success = "Thanks. We'll email you.",
  className,
}: {
  source: string;
  os?: string;
  cta?: string;
  placeholder?: string;
  success?: string;
  className?: string;
}) {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "loading" | "done" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (state === "loading") return;
    setState("loading");
    setError(null);
    try {
      const res = await fetch("/api/notify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, source, os }),
      });
      const data = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (!res.ok || !data?.ok) {
        setError(data?.error ?? "Something went wrong. Please try again.");
        setState("error");
        return;
      }
      trackJourneyEvent({
        eventName: "notify_submitted",
        area: "capture",
        payload: { source, os: os ?? "none" },
      });
      setState("done");
    } catch {
      setError("Something went wrong. Please try again.");
      setState("error");
    }
  }

  if (state === "done") {
    return (
      <p className={"inline-flex items-center gap-2 text-sm font-medium text-primary " + (className ?? "")}>
        <Check className="size-4" />
        {success}
      </p>
    );
  }

  return (
    <div className={"w-full max-w-md " + (className ?? "")}>
      <form onSubmit={onSubmit} className="flex flex-col gap-2 sm:flex-row">
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder={placeholder}
          aria-label="Email address"
          className="h-11 flex-1 rounded-full border border-border bg-background/70 px-4 text-sm text-foreground outline-none transition-colors placeholder:text-faint focus:border-primary/60"
        />
        <Button type="submit" disabled={state === "loading"} className="h-11 rounded-full px-5">
          {state === "loading" ? "Sending..." : cta}
          {state !== "loading" ? <ArrowUpRight className="size-4" /> : null}
        </Button>
      </form>
      {error ? <p className="mt-1.5 text-sm text-[#f0b429]">{error}</p> : null}
    </div>
  );
}

"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import {
  type JourneyPayload,
  trackJourneyEvent,
} from "@/lib/journey-events";

export function TrackedLinkButton({
  href,
  label,
  className,
  variant = "default",
  area,
  eventName,
  payload,
}: {
  href: string;
  label: string;
  className: string;
  variant?: "default" | "outline";
  area: string;
  eventName: string;
  payload: JourneyPayload;
}) {
  function trackClick() {
    trackJourneyEvent({
      eventName,
      area,
      payload: {
        ...payload,
        destination: href,
      },
    });
  }

  return (
    <Button
      variant={variant}
      render={<Link href={href} onClick={trackClick} />}
      className={className}
    >
      {label}
    </Button>
  );
}

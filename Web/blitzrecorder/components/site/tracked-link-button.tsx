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
  variant,
  size,
  area,
  eventName,
  payload,
}: {
  href: string;
  label: string;
  className: string;
  variant: "default" | "outline";
  size: "default" | "lg";
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
      size={size}
      render={<Link href={href} onClick={trackClick} />}
      className={className}
    >
      {label}
    </Button>
  );
}

"use client";

import type { ReactNode } from "react";
import { blitzreelsUrl } from "@/lib/blitzreels";
import { trackJourneyEvent } from "@/lib/journey-events";

export function BlitzReelsLink({
  content,
  className,
  children,
}: {
  content: string;
  className?: string;
  children: ReactNode;
}) {
  const href = blitzreelsUrl(content);

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener"
      className={className}
      onClick={() =>
        trackJourneyEvent({
          eventName: "blitzreels_clicked",
          area: "blitzreels",
          payload: {
            content,
            destination: href,
          },
        })
      }
    >
      {children}
    </a>
  );
}

"use client";

import { useEffect, useRef } from "react";
import {
  type JourneyPayload,
  trackJourneyEvent,
} from "@/lib/journey-events";

export function JourneyPageView({
  area,
  eventName,
  payload,
}: {
  area: string;
  eventName: string;
  payload: JourneyPayload;
}) {
  const tracked = useRef(false);

  useEffect(() => {
    if (tracked.current) {
      return;
    }
    tracked.current = true;
    trackJourneyEvent({ eventName, area, payload });
  }, [area, eventName, payload]);

  return null;
}

export function JourneySectionView({
  area,
  section,
  payload,
}: {
  area: string;
  section: string;
  payload: JourneyPayload;
}) {
  const markerRef = useRef<HTMLSpanElement>(null);
  const tracked = useRef(false);

  useEffect(() => {
    const marker = markerRef.current;
    if (!marker || tracked.current) {
      return;
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry?.isIntersecting || tracked.current) {
          return;
        }
        tracked.current = true;
        trackJourneyEvent({
          eventName: "section_viewed",
          area,
          payload: {
            section,
            ...payload,
          },
        });
        observer.disconnect();
      },
      { threshold: 0.35 },
    );

    observer.observe(marker);
    return () => observer.disconnect();
  }, [area, payload, section]);

  return <span ref={markerRef} aria-hidden className="sr-only" />;
}

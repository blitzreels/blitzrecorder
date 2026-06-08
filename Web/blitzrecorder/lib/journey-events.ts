"use client";

export type JourneyPayloadValue = string | number | boolean | null;
export type JourneyPayload = Record<string, JourneyPayloadValue>;

const DATAFAST_PARAM_LIMIT = 10;
const DATAFAST_VALUE_LIMIT = 255;

function normalizeValue({ value }: { value: JourneyPayloadValue }): string {
  if (value === null) {
    return "none";
  }
  return String(value).slice(0, DATAFAST_VALUE_LIMIT);
}

function getContext({ area }: { area: string }): JourneyPayload {
  if (typeof window === "undefined") {
    return { product: "blitzrecorder", journey_area: area };
  }

  return {
    product: "blitzrecorder",
    journey_area: area,
    path: window.location.pathname,
  };
}

function toDataFastPayload({
  payload,
}: {
  payload: JourneyPayload;
}): Record<string, string> {
  return Object.fromEntries(
    Object.entries(payload)
      .slice(0, DATAFAST_PARAM_LIMIT)
      .map(([key, value]) => [key, normalizeValue({ value })]),
  );
}

export function trackJourneyEvent({
  eventName,
  area,
  payload,
}: {
  eventName: string;
  area: string;
  payload: JourneyPayload;
}) {
  if (typeof window === "undefined") {
    return;
  }

  const fullPayload = {
    ...getContext({ area }),
    ...payload,
  };

  try {
    window.datafast?.(eventName, toDataFastPayload({ payload: fullPayload }));
  } catch {
    // Analytics should never block website journeys.
  }
}

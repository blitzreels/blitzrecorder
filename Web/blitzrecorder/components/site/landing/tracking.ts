import { trackJourneyEvent } from "@/lib/journey-events";

export function trackLandingCtaClicked({
  cta,
  destination,
}: {
  cta: string;
  destination: string;
}) {
  trackJourneyEvent({
    eventName: "landing_cta_clicked",
    area: "landing",
    payload: {
      cta,
      destination,
    },
  });
}

"use client";

import { useEffect } from "react";
import { trackJourneyEvent } from "@/lib/journey-events";

export function CheckoutReturnTracker() {
  useEffect(() => {
    const checkoutState = new URLSearchParams(window.location.search).get(
      "checkout",
    );
    if (checkoutState !== "cancel") {
      return;
    }
    trackJourneyEvent({
      eventName: "checkout_returned",
      area: "checkout",
      payload: {
        result: "cancel",
        destination: "#pricing",
      },
    });
  }, []);

  return null;
}

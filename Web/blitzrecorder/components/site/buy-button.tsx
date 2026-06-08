"use client";

import type { FormEvent } from "react";
import { CreditCard } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { trackJourneyEvent } from "@/lib/journey-events";

const ATTRIBUTION_PARAMS = [
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "gclid",
  "fbclid",
  "msclkid",
  "ttclid",
] as const;

function upsertHiddenInput(form: HTMLFormElement, name: string, value: string) {
  let input = form.querySelector<HTMLInputElement>(
    `input[type="hidden"][name="${name}"][data-checkout-attribution="true"]`,
  );
  if (!input) {
    input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.dataset.checkoutAttribution = "true";
    form.append(input);
  }
  input.value = value;
}

function writeAttributionInputs(form: HTMLFormElement) {
  upsertHiddenInput(
    form,
    "landing_path",
    `${window.location.pathname}${window.location.search}${window.location.hash}`,
  );

  if (document.referrer) {
    upsertHiddenInput(form, "landing_referrer", document.referrer);
  }

  const params = new URLSearchParams(window.location.search);
  for (const param of ATTRIBUTION_PARAMS) {
    const value = params.get(param);
    if (value) {
      upsertHiddenInput(form, param, value);
    }
  }
}

export function BuyButton({
  className,
  label = "Buy Lifetime License",
  source = "unknown",
}: {
  className?: string;
  label?: string;
  source?: string;
}) {
  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    writeAttributionInputs(event.currentTarget);
    trackJourneyEvent({
      eventName: "checkout_started",
      area: "checkout",
      payload: {
        plan: "early_lifetime",
        source,
        price: 39,
      },
    });
  }

  return (
    <form action="/api/checkout" method="POST" onSubmit={handleSubmit}>
      <input type="hidden" name="source" value={source} />
      <Button type="submit" className={className}>
        <CreditCard className="size-4" />
        {label}
      </Button>
    </form>
  );
}

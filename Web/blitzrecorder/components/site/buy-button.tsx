"use client";

import { useState, type FormEvent } from "react";
import { CreditCard } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { trackJourneyEvent } from "@/lib/journey-events";
import { cn } from "@/lib/utils";

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
  formClassName,
  label = "Buy Lifetime License",
  source = "unknown",
}: {
  className?: string;
  formClassName?: string;
  label?: string;
  source?: string;
}) {
  const [isSubmitting, setIsSubmitting] = useState(false);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    writeAttributionInputs(event.currentTarget);
    setIsSubmitting(true);
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
    <form
      action="/api/checkout"
      method="POST"
      onSubmit={handleSubmit}
      className={cn("flex flex-col gap-3", formClassName)}
    >
      <input type="hidden" name="source" value={source} />
      <label className="sr-only" htmlFor={`checkout-email-${source}`}>
        Email for receipt and license
      </label>
      <input
        id={`checkout-email-${source}`}
        type="email"
        name="email"
        required
        autoComplete="email"
        inputMode="email"
        placeholder="Email for receipt and license"
        className="h-12 w-full rounded-full border border-border bg-background/75 px-4 text-sm text-foreground outline-none transition placeholder:text-muted-foreground focus:border-primary/70 focus:ring-3 focus:ring-primary/20"
      />
      <Button type="submit" disabled={isSubmitting} className={className}>
        <CreditCard className="size-4" />
        {isSubmitting ? "Opening checkout..." : label}
      </Button>
    </form>
  );
}

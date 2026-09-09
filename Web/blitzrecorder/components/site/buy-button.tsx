"use client";

import { useState, type FormEvent } from "react";
import { Key } from "@/components/site/icons";
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

export function LicenseButton({
  className,
  formClassName,
  label = "Get free license",
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
      eventName: "license_started",
      area: "license",
      payload: {
        plan: "free",
        source,
        price: 0,
      },
    });
  }

  return (
    <form
      action="/api/licenses/issue"
      method="POST"
      onSubmit={handleSubmit}
      className={cn("flex flex-col gap-3", formClassName)}
    >
      <input type="hidden" name="source" value={source} />
      <label className="sr-only" htmlFor={`license-email-${source}`}>
        Email for your license key
      </label>
      <input
        id={`license-email-${source}`}
        type="email"
        name="email"
        required
        autoComplete="email"
        inputMode="email"
        placeholder="Email for your license key"
        className="h-12 w-full rounded-full border border-border bg-background/75 px-4 text-sm text-foreground outline-none transition placeholder:text-muted-foreground focus:border-primary/70 focus:ring-3 focus:ring-primary/20"
      />
      <Button type="submit" disabled={isSubmitting} className={className}>
        <Key className="size-4" />
        {isSubmitting ? "Issuing license..." : label}
      </Button>
    </form>
  );
}

/** @deprecated Use LicenseButton. Kept so older imports still compile. */
export const BuyButton = LicenseButton;

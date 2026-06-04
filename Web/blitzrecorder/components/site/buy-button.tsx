"use client";

import { CreditCard } from "@/components/site/icons";
import { Button } from "@/components/ui/button";

export function BuyButton({
  className,
  label = "Get Early Price",
}: {
  className?: string;
  label?: string;
}) {
  function trackCheckoutStart() {
    try {
      window.datafast?.("checkout_started", {
        product: "blitzrecorder",
        plan: "early_lifetime",
      });
    } catch {
      // Analytics should never block checkout.
    }
  }

  return (
    <form action="/api/checkout" method="POST" onSubmit={trackCheckoutStart}>
      <Button type="submit" className={className}>
        <CreditCard className="size-4" />
        {label}
      </Button>
    </form>
  );
}

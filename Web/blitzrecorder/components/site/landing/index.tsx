"use client";

import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { JourneyPageView } from "@/components/site/journey-markers";
import { useReveal } from "@/components/site/use-reveal";
import { CheckoutReturnTracker } from "@/components/site/landing/checkout-return-tracker";
import { ClosingCTA } from "@/components/site/landing/closing-cta";
import { Comparison } from "@/components/site/landing/comparison";
import { Faq } from "@/components/site/landing/faq";
import { Features } from "@/components/site/landing/features";
import { Hero } from "@/components/site/landing/hero";
import { HowToStart } from "@/components/site/landing/how-to-start";
import { IphoneCompanion } from "@/components/site/landing/iphone-companion";
import { Pricing } from "@/components/site/landing/pricing";
import { Setups } from "@/components/site/landing/setups";
import { TrustStrip } from "@/components/site/landing/trust-strip";

export function Landing() {
  useReveal();

  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <CheckoutReturnTracker />
      <JourneyPageView
        area="landing"
        eventName="landing_page_viewed"
        payload={{
          page: "home",
          open_source: true,
        }}
      />
      <SiteBackground />
      <SiteNav />
      <main>
        <Hero />
        <TrustStrip />
        <Features />
        <IphoneCompanion />
        <Setups />
        <Comparison />
        <Pricing />
        <HowToStart />
        <Faq />
        <ClosingCTA />
      </main>
      <SiteFooter />
    </div>
  );
}

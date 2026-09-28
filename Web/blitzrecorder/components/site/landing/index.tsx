"use client";

import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { JourneyPageView } from "@/components/site/journey-markers";
import { useReveal } from "@/components/site/use-reveal";
import { CameraChapter } from "@/components/site/landing/camera-chapter";
import { CheckoutReturnTracker } from "@/components/site/landing/checkout-return-tracker";
import { ClosingCTA } from "@/components/site/landing/closing-cta";
import { EditChapter } from "@/components/site/landing/edit-chapter";
import { ExportChapter } from "@/components/site/landing/export-chapter";
import { Faq } from "@/components/site/landing/faq";
import { Hero } from "@/components/site/landing/hero";
import { Pricing } from "@/components/site/landing/pricing";
import { RecordChapter } from "@/components/site/landing/record-chapter";
import { Toolbox } from "@/components/site/landing/toolbox";

export function Landing() {
  useReveal();

  return (
    <div className="relative min-h-screen overflow-x-clip">
      <CheckoutReturnTracker />
      <JourneyPageView
        area="landing"
        eventName="landing_page_viewed"
        payload={{ page: "home", open_source: true }}
      />
      <SiteNav />
      <main>
        <Hero />
        <RecordChapter />
        <CameraChapter />
        <EditChapter />
        <ExportChapter />
        <Toolbox />
        <Pricing />
        <Faq />
        <ClosingCTA />
      </main>
      <SiteFooter />
    </div>
  );
}

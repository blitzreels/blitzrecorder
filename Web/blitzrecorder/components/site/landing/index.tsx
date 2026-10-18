import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { JourneyPageView } from "@/components/site/journey-markers";
import { LoopingVideos } from "@/components/site/looping-videos";
import { CameraChapter } from "@/components/site/landing/camera-chapter";
import { CheckoutReturnTracker } from "@/components/site/landing/checkout-return-tracker";
import { Closing } from "@/components/site/landing/closing";
import { EditChapter } from "@/components/site/landing/edit-chapter";
import { Faq } from "@/components/site/landing/faq";
import { Hero } from "@/components/site/landing/hero";
import { HowItWorks } from "@/components/site/landing/how-it-works";
import { MadeWith } from "@/components/site/landing/made-with";
import { Pricing } from "@/components/site/landing/pricing";

export function Landing() {
  return (
    <div className="relative min-h-screen overflow-x-clip">
      <CheckoutReturnTracker />
      <JourneyPageView
        area="landing"
        eventName="landing_page_viewed"
        payload={{ page: "home", open_source: true }}
      />
      <SiteNav />
      <LoopingVideos />
      <main>
        <Hero />
        <HowItWorks />
        <MadeWith />
        <EditChapter />
        <Pricing />
        <CameraChapter />
        <Faq />
        <Closing />
      </main>
      <SiteFooter />
    </div>
  );
}

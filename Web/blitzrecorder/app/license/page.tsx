import type { Metadata } from "next";
import { BuyButton } from "@/components/site/buy-button";
import { JourneyPageView } from "@/components/site/journey-markers";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";

export const metadata: Metadata = {
  title: "License",
  description:
    "Buy the BlitzRecorder lifetime license. Stripe redirects you to a private claim page with your key.",
};

export default function LicensePage() {
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <JourneyPageView
        area="license"
        eventName="license_page_viewed"
        payload={{ page: "license" }}
      />
      <SiteBackground />
      <SiteNav />
      <main>
        <Section width="sm" className="grid min-h-[80vh] place-items-center pt-32 pb-24 text-center">
          <Card className="glass ring-gradient w-full ring-0">
            <CardContent className="p-8 sm:p-10">
              <Heading level={1} className="text-4xl leading-[1.02] sm:text-5xl">
                BlitzRecorder license
              </Heading>
              <Paragraph className="mt-4">
                Buy the $39 beta lifetime license. Stripe sends the receipt, then returns you here to activate
                BlitzRecorder.
              </Paragraph>
              <BuyButton
                label="Buy Lifetime License"
                source="license_page"
                formClassName="mt-7"
                className="h-11 rounded-full px-5"
              />
            </CardContent>
          </Card>
        </Section>
      </main>
      <SiteFooter />
    </div>
  );
}

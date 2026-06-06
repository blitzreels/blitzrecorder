import type { Metadata } from "next";
import { JourneyPageView } from "@/components/site/journey-markers";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { TrackedLinkButton } from "@/components/site/tracked-link-button";
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
              <Heading level={1}>BlitzRecorder license</Heading>
              <Paragraph className="mt-4">
                Buy the $39 beta lifetime license, then Stripe redirects you to a private claim page with your key.
              </Paragraph>
              <TrackedLinkButton
                href="/#pricing"
                label="Buy Lifetime License"
                className="mt-7 h-11 rounded-full px-5"
                area="license"
                eventName="license_cta_clicked"
                payload={{ cta: "buy_lifetime_license" }}
              />
            </CardContent>
          </Card>
        </Section>
      </main>
      <SiteFooter />
    </div>
  );
}

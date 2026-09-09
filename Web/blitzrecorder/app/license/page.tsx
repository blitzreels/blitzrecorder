import type { Metadata } from "next";
import { LicenseButton } from "@/components/site/buy-button";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
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
    "Get a free BlitzRecorder license. Enter your email, copy the key, unlock 4K, 60 fps, and optional iPhone camera.",
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
                Free BlitzRecorder license
              </Heading>
              <Paragraph className="mt-4">
                Enter your email. Copy the key. Paste it in Account. Unlocks 4K,
                60 fps, and optional iPhone camera. Same email always returns
                the same key.
              </Paragraph>
              <LicenseButton
                label="Get free license"
                source="license_page"
                formClassName="mt-7"
                className="h-11 rounded-full px-5"
              />
              <Paragraph tone="faint" size="sm" className="mt-6">
                A{" "}
                <BlitzReelsLink
                  content="license_page"
                  className="font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
                >
                  BlitzReels
                </BlitzReelsLink>{" "}
                company product. Recorder stays on your Mac. Clips and captions
                live in BlitzReels.
              </Paragraph>
            </CardContent>
          </Card>
        </Section>
      </main>
      <SiteFooter />
    </div>
  );
}

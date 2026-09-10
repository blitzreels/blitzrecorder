import type { Metadata } from "next";
import { LicenseButton } from "@/components/site/buy-button";
import { DownloadButton } from "@/components/site/download-button";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { JourneyPageView } from "@/components/site/journey-markers";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";

export const metadata: Metadata = {
  title: "Free app and legacy licenses",
  description:
    "BlitzRecorder 0.15 and later includes all features without a license key. Download the app or recover a key for an older version.",
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
                No license key needed
              </Heading>
              <Paragraph className="mt-4">
                BlitzRecorder 0.15 and later includes 4K export, 60 fps export,
                and iPhone camera recording. No account or email required.
              </Paragraph>
              <DownloadButton
                source="license_page_download"
                className="mt-7 h-11 rounded-full px-5"
              />
              <details className="mt-8 border-t border-border pt-6 text-left">
                <summary className="cursor-pointer font-medium">Using an older version?</summary>
                <Paragraph size="sm" className="mt-3">
                  Versions before 0.15 can still use a free license key. Enter
                  your email to retrieve it, then paste it in Account in that version.
                </Paragraph>
                <LicenseButton
                  label="Get legacy license"
                  source="license_page_legacy"
                  formClassName="mt-4"
                  className="h-11 rounded-full px-5"
                />
              </details>
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

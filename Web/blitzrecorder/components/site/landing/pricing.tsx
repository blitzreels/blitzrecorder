import { DownloadButton } from "@/components/site/download-button";
import { CheckItem } from "@/components/site/check-item";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { license, requirements } from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";

export function Pricing() {
  return (
    <Section width="lg" id="license" className="scroll-mt-24 py-28">
      <JourneySectionView
        area="landing"
        section="license"
        payload={{ page: "home" }}
      />
      <div className="mx-auto max-w-2xl text-center">
        <div data-reveal className="flex justify-center">
          <Eyebrow center>Free app</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5">
          All features. Free.
        </Heading>
        <Paragraph data-reveal className="mt-5">
          Record, edit, and export in 4K at 60 fps. No account, email, or license
          key needed.
        </Paragraph>
      </div>

      <div className="mx-auto mt-14 max-w-xl" data-reveal>
        <Card className="glass ring-gradient gap-0 py-8 ring-0">
          <CardContent className="px-8">
            <p className="font-display text-5xl font-black tracking-tight tabular-nums">$0</p>
            <Paragraph tone="default" size="sm" className="mt-3 font-semibold text-primary">
              Free download
            </Paragraph>
            <ul className="mt-7 flex flex-col gap-3.5 text-[15px]">
              {license.features.map((feature) => (
                <CheckItem key={feature}>{feature}</CheckItem>
              ))}
            </ul>
            <DownloadButton
              source="home_free_app"
              className="mt-8 h-12 w-full rounded-full text-base"
            />
          </CardContent>
        </Card>
      </div>

      <Paragraph tone="faint" size="sm" className="mt-6 text-center" data-reveal>
        Requires {requirements.macos}.
      </Paragraph>
    </Section>
  );
}

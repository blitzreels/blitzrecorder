import Image from "next/image";
import { ArrowUpRight } from "@/components/site/icons";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { Eyebrow } from "@/components/site/landing/eyebrow";

export function Company() {
  return (
    <Section width="md" className="py-24">
      <JourneySectionView
        area="landing"
        section="company"
        payload={{ page: "home" }}
      />
      <div className="mx-auto max-w-2xl text-center">
        <div data-reveal className="flex justify-center">
          <Eyebrow center>A BlitzReels product</Eyebrow>
        </div>
        <Image
          src={assets.blitzreelsWordmark}
          alt="BlitzReels"
          width={190}
          height={40}
          data-reveal
          className="mx-auto mt-8 h-8 w-auto opacity-90"
        />
        <Heading level={2} data-reveal className="mt-6">
          Built for short-form. Clips live in BlitzReels.
        </Heading>
        <Paragraph data-reveal className="mt-5">
          Recorder is the free local Mac studio. Same company. Send a take when
          you want captions and publish.
        </Paragraph>
        <div data-reveal className="mt-8">
          <BlitzReelsLink
            content="landing_company"
            className="inline-flex h-12 items-center gap-2 rounded-full bg-primary px-7 text-base font-medium text-primary-foreground"
          >
            Open BlitzReels
            <ArrowUpRight className="size-4" />
          </BlitzReelsLink>
        </div>
      </div>
    </Section>
  );
}

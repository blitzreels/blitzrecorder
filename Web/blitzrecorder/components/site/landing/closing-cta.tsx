import Image from "next/image";
import { DownloadButton } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";

export function ClosingCTA() {
  return (
    <Section width="sm" className="grid place-items-center py-28 text-center">
      <JourneySectionView
        area="landing"
        section="closing_cta"
        payload={{ page: "home" }}
      />
      <Image
        src={assets.macIcon}
        width={80}
        height={80}
        alt=""
        data-reveal
        className="rounded-[22%]"
      />
      <Heading level={2} data-reveal className="mt-8">
        Get the Mac app.
      </Heading>
      <Paragraph data-reveal className="mt-5">
        Free open-source screen recorder for short-form. Files stay on your Mac.
      </Paragraph>
      <div data-reveal className="mt-8">
        <DownloadButton
          source="home_closing"
          className="h-12 rounded-full px-7 text-base"
        />
      </div>
    </Section>
  );
}

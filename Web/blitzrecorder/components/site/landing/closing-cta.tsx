import Image from "next/image";
import { DownloadButton } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading } from "@/components/ui/typography";
import { assets } from "@/lib/assets";

export function ClosingCTA() {
  return (
    <Section className="grid place-items-center pt-8 pb-32 text-center">
      <JourneySectionView area="landing" section="closing_cta" payload={{ page: "home" }} />
      <Image
        src={assets.macIcon}
        width={88}
        height={88}
        alt=""
        data-reveal
        className="rounded-[22%]"
      />
      <Heading level={2} data-reveal className="mt-9 max-w-[13ch]">
        Press record. <span className="text-muted-foreground">Edit it right here.</span>
      </Heading>
      <div data-reveal className="mt-10">
        <DownloadButton source="home_closing" size="lg" label="Download for Mac" className="" />
      </div>
    </Section>
  );
}

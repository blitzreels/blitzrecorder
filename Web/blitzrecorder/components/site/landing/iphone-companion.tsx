import Image from "next/image";
import { CheckItem } from "@/components/site/check-item";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { Eyebrow } from "@/components/site/landing/eyebrow";

export function IphoneCompanion() {
  return (
    <Section
      id="iphone"
      className="grid items-center gap-12 py-20 lg:grid-cols-[0.85fr_1.15fr] lg:gap-20"
    >
      <JourneySectionView
        area="landing"
        section="iphone_companion"
        payload={{ page: "home" }}
      />
      <div data-reveal className="relative mx-auto">
        <div aria-hidden className="pointer-events-none absolute inset-0 -z-10">
          <div
            className="size-full"
            style={{
              background:
                "radial-gradient(50% 50% at 50% 45%, rgba(94,242,175,0.22), transparent 70%)",
            }}
          />
        </div>
        <div className="ring-gradient w-[min(320px,76vw)] rounded-[44px] bg-muted/70 p-3 shadow-[0_50px_110px_-45px_rgba(0,0,0,0.95)] backdrop-blur-xl">
          <Image
            src={assets.iosPhone}
            alt="BlitzRecorder Camera companion app on iPhone"
            sizes="320px"
            className="h-auto w-full rounded-[32px]"
          />
        </div>
      </div>
      <div>
        <div data-reveal>
          <Eyebrow>iPhone camera</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5 sm:text-5xl">
          Shot on the iPhone you already own.
        </Heading>
        <Paragraph data-reveal className="mt-6 max-w-xl">
          The iPhone records locally at full resolution, so quality never drops
          to a live video stream. When you stop, it hands the file off to your
          Mac automatically.
        </Paragraph>
        <ul data-reveal className="mt-8 flex flex-col gap-3.5 text-lg">
          <CheckItem>Records locally at full resolution</CheckItem>
          <CheckItem>Framed and controlled from your Mac</CheckItem>
          <CheckItem>Transfers to your Mac automatically</CheckItem>
        </ul>
      </div>
    </Section>
  );
}

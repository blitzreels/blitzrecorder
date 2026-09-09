import Image from "next/image";
import { CheckItem } from "@/components/site/check-item";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { studioBeats } from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";

export function Features() {
  return (
    <Section
      id="how"
      className="grid scroll-mt-24 items-center gap-12 py-24 lg:grid-cols-[1.1fr_0.9fr] lg:gap-20"
    >
      <JourneySectionView
        area="landing"
        section="features"
        payload={{ page: "home" }}
      />
      <div>
        <div data-reveal>
          <Eyebrow>The app</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5 sm:text-5xl">
          Capture, cut, export.
        </Heading>
        <Paragraph data-reveal className="mt-6 max-w-xl">
          Screen, mic, and system audio into a take. Then a timeline in the same
          app so the cut is short-form ready.
        </Paragraph>
        <ul data-reveal className="mt-8 flex flex-col gap-5">
          {studioBeats.map((beat) => (
            <CheckItem key={beat.title}>
              <span className="font-semibold text-foreground">{beat.title}.</span>{" "}
              <span className="text-muted-foreground">{beat.body}</span>
            </CheckItem>
          ))}
        </ul>
      </div>
      <div data-reveal className="relative mx-auto w-full max-w-lg">
        <Image
          src={assets.macPlan}
          alt="BlitzRecorder studio on macOS"
          sizes="(min-width: 1024px) 480px, 100vw"
          className="h-auto w-full rounded-xl ring-1 ring-white/10 shadow-[0_40px_90px_-40px_rgba(0,0,0,0.9)]"
        />
      </div>
    </Section>
  );
}

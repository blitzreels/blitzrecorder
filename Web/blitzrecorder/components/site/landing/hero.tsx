import { JourneySectionView } from "@/components/site/journey-markers";
import { GetApp } from "@/components/site/landing/get-app";
import { StudioMockup } from "@/components/site/studio-mockup";
import { Section } from "@/components/ui/layout";

export function Hero() {
  return (
    <div className="overflow-x-clip">
      <Section width="page" className="pt-32 pb-16 sm:pt-40 sm:pb-24">
        <JourneySectionView area="landing" section="hero" payload={{ page: "home" }} />
        <div className="mx-auto flex flex-col items-center text-center">
          <h1 className="type-hero text-[clamp(2.75rem,5.6vw,4.5rem)]">
            Record your screen and your face.
            <br />
            Post it the same day.
          </h1>
          <p className="mt-6 max-w-[42ch] text-lg leading-7 text-pretty text-muted-foreground sm:text-xl sm:leading-8">
            BlitzRecorder is a free Mac app. It frames your take for YouTube and Shorts and cuts the pauses
            for you.
          </p>
          <div className="mt-9">
            <GetApp source="home_hero" align="center" />
          </div>
        </div>

        <StudioMockup className="mt-14 ml-2 w-[160vw] max-w-none sm:mx-0 sm:mt-20 sm:w-full" priority />
      </Section>
    </div>
  );
}

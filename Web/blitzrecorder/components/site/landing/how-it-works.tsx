import { LandingSection } from "@/components/site/landing/landing-section";
import { StepList } from "@/components/site/step-list";
import { landingSteps } from "@/lib/content";

export function HowItWorks() {
  return (
    <LandingSection
      id="how"
      section="how_it_works"
      title="From one take to a finished video."
      intro="Three steps, all in one app on your Mac."
      action={null}
    >
      <StepList steps={landingSteps} />
    </LandingSection>
  );
}

import { FeatureIcon } from "@/components/site/icons";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { features } from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";
import { revealDelay } from "@/components/site/landing/reveal";

export function Features() {
  return (
    <Section id="how" className="scroll-mt-24 py-28">
      <JourneySectionView
        area="landing"
        section="features"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>One recorder</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-3xl text-center">
        Every source, <span className="text-gradient">one recorder.</span>
      </Heading>
      <Paragraph data-reveal className="mx-auto mt-6 max-w-2xl text-center">
        Capture your screen, camera, microphone, and system audio into a single
        composed frame. Arrange the shot once, then record start to finish.
      </Paragraph>
      <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feat, i) => (
          <Card
            key={feat.title}
            data-reveal
            style={revealDelay(`${(i % 3) * 90}ms`)}
            className="glass ring-gradient gap-0 py-0 ring-0"
          >
            <CardContent className="flex flex-col gap-3 p-6">
              <span className="inline-flex size-10 items-center justify-center rounded-xl bg-primary/10 text-primary ring-1 ring-primary/20">
                <FeatureIcon name={feat.icon} className="size-5" />
              </span>
              <Heading level={3}>{feat.title}</Heading>
              <Paragraph size="base">{feat.body}</Paragraph>
            </CardContent>
          </Card>
        ))}
      </div>
    </Section>
  );
}

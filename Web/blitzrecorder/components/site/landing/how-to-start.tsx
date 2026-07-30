import { JourneySectionView } from "@/components/site/journey-markers";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { Eyebrow } from "@/components/site/landing/eyebrow";
import { revealDelay } from "@/components/site/landing/reveal";

const steps = [
  {
    n: "01",
    title: "Download and open",
    body: "Drag BlitzRecorder to your Applications folder and open it. No account and no sign up.",
  },
  {
    n: "02",
    title: "Approve permissions",
    body: "Allow screen recording, camera, and microphone when macOS asks. It takes a few clicks, one time.",
  },
  {
    n: "03",
    title: "Set up and record",
    body: "Pick your layout, pair your iPhone if you want it, and hit record. What you see is what you get.",
  },
];

export function HowToStart() {
  return (
    <Section className="py-20">
      <JourneySectionView
        area="landing"
        section="how_to_start"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>Get started</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-2xl text-center">
        Recording in three steps.
      </Heading>
      <div className="mx-auto mt-14 grid max-w-4xl gap-5 md:grid-cols-3">
        {steps.map((step, i) => (
          <Card
            key={step.n}
            data-reveal
            style={revealDelay(`${i * 90}ms`)}
            className="glass ring-gradient gap-0 py-0 ring-0"
          >
            <CardContent className="flex flex-col gap-3 p-6">
              <span className="font-mono text-sm font-semibold text-primary">{step.n}</span>
              <Heading level={3}>{step.title}</Heading>
              <Paragraph size="base">{step.body}</Paragraph>
            </CardContent>
          </Card>
        ))}
      </div>
    </Section>
  );
}

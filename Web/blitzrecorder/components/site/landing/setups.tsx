import Image from "next/image";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { setups } from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";
import { revealDelay } from "@/components/site/landing/reveal";

export function Setups() {
  return (
    <Section className="py-20">
      <JourneySectionView
        area="landing"
        section="setups"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>Two setups</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-3xl text-center">
        Two ways to record.
      </Heading>
      <div className="mx-auto mt-14 grid max-w-4xl gap-5 md:grid-cols-2">
        {setups.map((card, i) => (
          <Card
            key={card.title}
            data-reveal
            style={revealDelay(`${i * 110}ms`)}
            className="glass ring-gradient group/card gap-0 py-0 ring-0 transition-all duration-500 hover:-translate-y-1.5 hover:shadow-[0_40px_90px_-45px_rgba(94,242,175,0.5)]"
          >
            <div className="relative overflow-hidden">
              <Image
                src={card.image}
                alt={card.title}
                sizes="(min-width: 768px) 520px, 100vw"
                className="h-auto w-full transition-transform duration-700 group-hover/card:scale-[1.04]"
              />
            </div>
            <CardContent className="p-6">
              <Heading level={3}>{card.title}</Heading>
              <Paragraph size="base" className="mt-3">
                {card.body}
              </Paragraph>
            </CardContent>
          </Card>
        ))}
      </div>
    </Section>
  );
}

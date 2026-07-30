"use client";

import { ChevronDown } from "@/components/site/icons";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { faqs } from "@/lib/content";
import { trackJourneyEvent } from "@/lib/journey-events";
import { Eyebrow } from "@/components/site/landing/eyebrow";

export function Faq() {
  return (
    <Section width="md" id="faq" className="scroll-mt-24 py-24">
      <JourneySectionView
        area="landing"
        section="faq"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>FAQ</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-2xl text-center">
        Questions, answered.
      </Heading>
      <div className="mx-auto mt-12 flex max-w-2xl flex-col gap-3">
        {faqs.map((item) => (
          <details
            key={item.q}
            data-reveal
            onToggle={(event) => {
              if (event.currentTarget.open) {
                trackJourneyEvent({
                  eventName: "faq_opened",
                  area: "landing",
                  payload: {
                    question: item.q,
                  },
                });
              }
            }}
            className="group glass ring-gradient overflow-hidden rounded-xl ring-0"
          >
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 font-medium text-foreground [&::-webkit-details-marker]:hidden">
              {item.q}
              <ChevronDown className="size-4 shrink-0 text-muted-foreground transition-transform duration-300 group-open:rotate-180" />
            </summary>
            <div className="px-5 pb-5">
              <Paragraph size="base" className="max-w-xl">
                {item.a}
              </Paragraph>
            </div>
          </details>
        ))}
      </div>
    </Section>
  );
}

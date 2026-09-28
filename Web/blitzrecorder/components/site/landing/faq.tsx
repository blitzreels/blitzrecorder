"use client";

import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading } from "@/components/ui/typography";
import { faqs } from "@/lib/content";
import { trackJourneyEvent } from "@/lib/journey-events";

export function Faq() {
  return (
    <Section id="faq" className="scroll-mt-24 py-20 sm:py-28">
      <JourneySectionView area="landing" section="faq" payload={{ page: "home" }} />
      <div className="grid gap-12 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:gap-20">
        <Heading level={2} data-reveal className="max-w-[10ch]">
          Questions, answered.
        </Heading>
        <div className="flex flex-col">
          {faqs.map((item) => (
            <details
              key={item.q}
              data-reveal
              onToggle={(event) => {
                if (event.currentTarget.open) {
                  trackJourneyEvent({
                    eventName: "faq_opened",
                    area: "landing",
                    payload: { question: item.q },
                  });
                }
              }}
              className="group border-t border-separator last:border-b"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 font-display text-lg font-bold tracking-[-0.01em] [&::-webkit-details-marker]:hidden">
                {item.q}
                <span
                  aria-hidden
                  className="relative size-4 shrink-0 text-muted-foreground transition-transform duration-300 group-open:rotate-45"
                >
                  <span className="absolute inset-x-0 top-1/2 h-[1.5px] -translate-y-1/2 rounded-full bg-current" />
                  <span className="absolute inset-y-0 left-1/2 w-[1.5px] -translate-x-1/2 rounded-full bg-current" />
                </span>
              </summary>
              <p className="max-w-xl pb-6 text-[15px] leading-7 text-muted-foreground">{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </Section>
  );
}

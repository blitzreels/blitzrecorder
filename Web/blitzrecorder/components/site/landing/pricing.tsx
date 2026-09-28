import { Check } from "@/components/site/icons";
import { DownloadButton } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { freeIncludes, macCompatibility } from "@/lib/content";

export function Pricing() {
  return (
    <Section id="free" className="scroll-mt-24 py-12 sm:py-16">
      <JourneySectionView area="landing" section="license" payload={{ page: "home" }} />
      <div
        data-reveal
        className="panel rounded-card px-6 py-12 sm:px-12 sm:py-16"
      >
        <div className="grid gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.9fr)] lg:items-center lg:gap-20">
          <div>
            <p className="label-mono text-primary">Price</p>
            <p className="mt-5 font-display text-[clamp(5rem,14vw,9rem)] leading-[0.8] font-extrabold tracking-[-0.06em]">
              $0
            </p>
            <Heading level={3} as="h2" className="mt-8 max-w-[16ch] text-[clamp(1.75rem,3.4vw,2.5rem)] leading-[1.02] font-extrabold tracking-[-0.035em]">
              Every feature, for everyone.
            </Heading>
            <Paragraph className="mt-4 max-w-md">
              No trial, no tiers, no card. Built by BlitzReels, with the code in public.
            </Paragraph>
          </div>
          <div>
            <ul className="flex flex-col">
              {freeIncludes.map((item) => (
                <li key={item} className="flex items-center gap-3 border-t border-separator py-3.5 first:border-t-0">
                  <Check className="size-4 shrink-0 text-primary" strokeWidth={2.5} />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
            <DownloadButton source="home_free_app" size="lg" label="Download for Mac" className="mt-7 w-full" />
            <p className="mt-3 text-center text-sm text-faint">{macCompatibility}</p>
          </div>
        </div>
      </div>
    </Section>
  );
}

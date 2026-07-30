import { Check } from "@/components/site/icons";
import { Section } from "@/components/ui/layout";

const trustItems = [
  "No account, ever",
  "Recordings stay on your Mac",
  "Pay once, no subscription",
  "30-day money-back guarantee",
  "From the makers of BlitzReels",
];

export function TrustStrip() {
  return (
    <Section width="lg" className="pb-6 pt-0 sm:pb-10">
      <div
        data-reveal
        className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3"
      >
        {trustItems.map((item) => (
          <span
            key={item}
            className="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground"
          >
            <Check className="size-4 text-primary" />
            {item}
          </span>
        ))}
      </div>
    </Section>
  );
}

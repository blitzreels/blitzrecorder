import { LandingSection } from "@/components/site/landing/landing-section";
import { faqs } from "@/lib/content";

/** Answers stay open: the doubts a buyer has should never sit behind a click. */
export function Faq() {
  return (
    <LandingSection
      id="faq"
      section="faq"
      title="Questions, answered."
      intro="What people ask before they download."
      action={null}
    >
      <dl className="grid gap-x-16 gap-y-10 md:grid-cols-2">
        {faqs.map((item) => (
          <div key={item.q}>
            <dt className="text-[17px] font-semibold tracking-[-0.01em] text-balance">{item.q}</dt>
            <dd className="mt-2 max-w-[52ch] text-[15px] leading-6 text-muted-foreground">{item.a}</dd>
          </div>
        ))}
      </dl>
    </LandingSection>
  );
}

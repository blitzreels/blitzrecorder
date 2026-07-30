import { BuyButton } from "@/components/site/buy-button";
import { CheckItem } from "@/components/site/check-item";
import { DownloadButton } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { GITHUB_REPO_URL } from "@/lib/release";
import {
  pricing,
  requirements,
  type Plan,
} from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";
import { revealDelay } from "@/components/site/landing/reveal";
import { trackLandingCtaClicked } from "@/components/site/landing/tracking";

export function Pricing() {
  return (
    <Section width="lg" id="pricing" className="scroll-mt-24 py-28">
      <JourneySectionView
        area="landing"
        section="pricing"
        payload={{ page: "home" }}
      />
      <div className="mx-auto max-w-2xl text-center">
        <div data-reveal className="flex justify-center">
          <Eyebrow center>Pricing</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5">
          Free to record. Pay once for the full studio.
        </Heading>
        <Paragraph data-reveal className="mt-5">
          The Mac app is free. One payment of $39 unlocks the iPhone camera, 4K,
          and 60 fps export. Pay once, with no subscription ever.
        </Paragraph>
      </div>

      <div className="mx-auto mt-14 grid max-w-3xl gap-5 md:grid-cols-2">
        <div data-reveal>
          <PlanCard plan={pricing.free} />
        </div>
        <div data-reveal style={revealDelay("110ms")}>
          <PlanCard plan={pricing.early} featured />
        </div>
      </div>

      <Paragraph tone="faint" size="sm" className="mt-6 text-center" data-reveal>
        Requires {requirements.macos}. The iPhone camera needs {requirements.ios}.
      </Paragraph>
      <p className="mt-3 text-center text-xs text-faint" data-reveal>
        <a
          href={GITHUB_REPO_URL}
          target="_blank"
          rel="noopener"
          onClick={() =>
            trackLandingCtaClicked({
              cta: "pricing_github_repo",
              destination: GITHUB_REPO_URL,
            })
          }
          className="font-medium text-muted-foreground underline-offset-4 transition-colors hover:text-foreground hover:underline"
        >
          GitHub repo
        </a>
      </p>
    </Section>
  );
}

function PlanCard({ plan, featured = false }: { plan: Plan; featured?: boolean }) {
  return (
    <div className="relative h-full">
      {featured ? (
        <div
          aria-hidden
          className="pointer-events-none absolute -inset-4 -z-10 rounded-[2rem] opacity-70"
          style={{
            background:
              "radial-gradient(60% 50% at 50% 30%, rgba(94,242,175,0.22), transparent 70%)",
            animation: "br-glow 6s ease-in-out infinite",
          }}
        />
      ) : null}
      <Card
        className={
          featured
            ? "ring-gradient h-full gap-0 bg-primary/[0.07] py-8 ring-0 shadow-[0_40px_100px_-60px_rgba(94,242,175,0.9)]"
            : "glass ring-gradient h-full gap-0 py-8 ring-0"
        }
      >
        <CardHeader className="px-8">
          <CardTitle className="font-display text-lg font-bold">{plan.name}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-1 flex-col px-8">
          <p className="flex flex-wrap items-baseline gap-x-2 gap-y-1 font-display tabular-nums">
            <span className="text-5xl font-black tracking-tight">{plan.price}</span>
            {plan.regularPrice ? (
              <span className="text-2xl font-bold text-muted-foreground line-through decoration-2">
                {plan.regularPrice}
              </span>
            ) : null}
            {plan.suffix ? <span className="text-base font-semibold text-muted-foreground">{plan.suffix}</span> : null}
          </p>
          <div className="mt-2 flex h-6 items-center gap-2 text-sm text-muted-foreground">
            {plan.subline ? <span>{plan.subline}</span> : null}
            {plan.save ? (
              <Badge variant="outline" className="border-primary/40 text-primary">
                {plan.save}
              </Badge>
            ) : null}
          </div>
          <Paragraph tone="default" size="sm" className="mt-3 font-semibold text-primary">
            {plan.note}
          </Paragraph>

          <ul className="mt-7 flex flex-col gap-3.5 text-[15px]">
            {plan.features.map((feature) => (
              <CheckItem key={feature}>{feature}</CheckItem>
            ))}
          </ul>

          <div className="grow" />

          {plan.cta === "buy" ? (
            <BuyButton
              label={plan.ctaLabel}
              source={featured ? "home_pricing_early" : "home_pricing_free"}
              formClassName="mt-8"
              className={
                "h-12 w-full rounded-full text-base" +
                (featured ? " shadow-[0_20px_50px_-20px_rgba(94,242,175,0.9)]" : "")
              }
            />
          ) : (
            <DownloadButton
              variant={featured ? "default" : "outline"}
              label={plan.ctaLabel}
              source={featured ? "home_pricing_early" : "home_pricing_free"}
              className={
                "mt-8 h-12 w-full rounded-full text-base" +
                (featured ? " shadow-[0_20px_50px_-20px_rgba(94,242,175,0.9)]" : "")
              }
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

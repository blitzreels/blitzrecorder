"use client";

import { useEffect, type CSSProperties } from "react";
import Image from "next/image";
import { ChevronDown, FeatureIcon, Check, Close } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { SiteNav } from "@/components/site/site-nav";
import { SiteFooter } from "@/components/site/site-footer";
import { WatchFilm } from "@/components/site/watch-film";
import { SiteBackground } from "@/components/site/site-background";
import { CheckItem } from "@/components/site/check-item";
import { BuyButton } from "@/components/site/buy-button";
import {
  JourneyPageView,
  JourneySectionView,
} from "@/components/site/journey-markers";
import {
  DownloadButton,
  DownloadMeta,
} from "@/components/site/download-button";
import { useReveal } from "@/components/site/use-reveal";
import { trackJourneyEvent } from "@/lib/journey-events";
import { GITHUB_REPO_URL } from "@/lib/release";
import { assets } from "@/lib/assets";
import {
  features,
  setups,
  faqs,
  pricing,
  requirements,
  comparison,
  type Plan,
} from "@/lib/content";

/** Stagger a reveal; cast covers csstype not knowing CSS custom properties. */
const revealDelay = (ms: string): CSSProperties =>
  ({ "--reveal-delay": ms }) as CSSProperties;

function trackLandingCtaClicked({
  cta,
  destination,
}: {
  cta: string;
  destination: string;
}) {
  trackJourneyEvent({
    eventName: "landing_cta_clicked",
    area: "landing",
    payload: {
      cta,
      destination,
    },
  });
}

export function Landing() {
  useReveal();
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <CheckoutReturnTracker />
      <JourneyPageView
        area="landing"
        eventName="landing_page_viewed"
        payload={{
          page: "home",
          open_source: true,
        }}
      />
      <SiteBackground />
      <SiteNav />
      <main>
        <Hero />
        <TrustStrip />
        <Features />
        <IphoneCompanion />
        <Setups />
        <Comparison />
        <Pricing />
        <HowToStart />
        <Faq />
        <ClosingCTA />
      </main>
      <SiteFooter />
    </div>
  );
}

function CheckoutReturnTracker() {
  useEffect(() => {
    const checkoutState = new URLSearchParams(window.location.search).get(
      "checkout",
    );
    if (checkoutState !== "cancel") {
      return;
    }
    trackJourneyEvent({
      eventName: "checkout_returned",
      area: "checkout",
      payload: {
        result: "cancel",
        destination: "#pricing",
      },
    });
  }, []);

  return null;
}

function AppleLogo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 384 512" aria-hidden fill="currentColor" className={className}>
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

function Eyebrow({ children, center }: { children: React.ReactNode; center?: boolean }) {
  return (
    <span
      className={
        "inline-flex items-center gap-2.5 text-xs font-semibold uppercase tracking-[0.2em] text-primary" +
        (center ? " justify-center" : "")
      }
    >
      <span className="h-px w-7 bg-gradient-to-r from-transparent to-primary/70" />
      {children}
    </span>
  );
}

function Hero() {
  return (
    <Section className="relative grid items-center gap-9 pt-24 pb-24 sm:gap-14 sm:pt-40 xl:grid-cols-[1fr_1.18fr] xl:gap-12">
      <JourneySectionView
        area="landing"
        section="hero"
        payload={{ page: "home" }}
      />
      {/* Left — copy */}
      <div className="text-center xl:text-left">
        <Heading
          level={1}
          data-reveal
          // clamp keeps "studio quality." on one line down to 320px-wide phones
          className="mx-auto max-w-[15ch] text-[clamp(2.25rem,14vw_-_8px,3rem)] leading-[0.94] sm:text-7xl xl:mx-0 xl:text-[4.4rem]"
          style={revealDelay("60ms")}
        >
          Short video,
          <br />
          <span className="text-gradient">studio quality.</span>
        </Heading>
        <Paragraph
          data-reveal
          className="mx-auto mt-5 max-w-xl text-balance sm:mt-6 sm:text-xl xl:mx-0"
          style={revealDelay("120ms")}
        >
          Your iPhone is the camera, and it records in full quality on the
          phone, so your video looks better than Continuity Camera. You set up
          the whole shot from your{" "}
          <span className="font-semibold whitespace-nowrap text-foreground">
            <AppleLogo className="mr-1.5 inline-block h-[0.85em] w-auto align-[-0.08em]" />
            Mac
          </span>
          .
        </Paragraph>
        <div
          data-reveal
          className="mt-7 flex flex-col items-center gap-3 min-[480px]:flex-row min-[480px]:flex-wrap min-[480px]:justify-center sm:mt-8 xl:justify-start"
          style={revealDelay("180ms")}
        >
          {/* One primary action above the fold: download free. The $39 unlock
              is a deliberate, quiet secondary — the purchase decision belongs in
              the Pricing section, after the demo. */}
          <DownloadButton
            source="home_hero"
            className="h-12 w-full max-w-80 rounded-full px-7 text-base shadow-[0_20px_60px_-22px_rgba(94,242,175,0.95)] transition-transform hover:scale-[1.03] min-[480px]:w-auto"
          />
          <Button
            variant="outline"
            render={<a href="#how" />}
            onClick={() =>
              trackLandingCtaClicked({
                cta: "hero_see_how",
                destination: "#how",
              })
            }
            className="hidden h-12 rounded-full px-7 text-base min-[480px]:inline-flex"
          >
            See how it works
          </Button>
          <a
            href="#how"
            onClick={() =>
              trackLandingCtaClicked({
                cta: "hero_see_how_mobile",
                destination: "#how",
              })
            }
            className="inline-flex items-center gap-1.5 py-1 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground min-[480px]:hidden"
          >
            See how it works
            <ChevronDown className="size-4" />
          </a>
        </div>
        <a
          href="#pricing"
          data-reveal
          onClick={() =>
            trackLandingCtaClicked({
              cta: "hero_unlock_link",
              destination: "#pricing",
            })
          }
          className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          style={revealDelay("210ms")}
        >
          or unlock the iPhone camera for $39
          <ChevronDown className="size-4 -rotate-90" />
        </a>
        <Paragraph
          tone="faint"
          size="sm"
          className="mt-4 sm:mt-5"
          data-reveal
          style={revealDelay("240ms")}
        >
          Free 1080p app · $39 unlocks the full studio · AGPL source
        </Paragraph>
        <div data-reveal className="mt-2" style={revealDelay("280ms")}>
          {/* compact: phones skip the requirements line — it lives in Pricing. */}
          <DownloadMeta compact className="text-sm" />
        </div>
      </div>

      {/* Right — device scene: Mac studio with the iPhone floating over its corner */}
      <div
        data-reveal
        className="relative mx-auto w-full max-w-xl xl:max-w-none"
        style={revealDelay("220ms")}
      >
        {/* emerald spotlight behind the window */}
        <div aria-hidden className="pointer-events-none absolute -inset-x-10 -top-16 -bottom-12 -z-10">
          <div
            className="size-full"
            style={{
              background:
                "radial-gradient(55% 55% at 55% 45%, rgba(94,242,175,0.26), transparent 72%)",
            }}
          />
        </div>

        {/* MacBook: aluminum rim, black bezel with camera notch, bottom deck */}
        <div className="w-full">
          <div className="rounded-[20px] bg-gradient-to-b from-[#5b5b60] to-[#26262a] p-[2px] shadow-[0_50px_120px_-40px_rgba(0,0,0,0.9)]">
            <div className="relative rounded-[18px] bg-[#08080a] p-2 sm:p-2.5">
              <div
                aria-hidden
                className="absolute left-1/2 top-0 z-10 flex h-4 w-[18%] max-w-[120px] -translate-x-1/2 items-center justify-center rounded-b-[7px] bg-[#08080a]"
              >
                <span className="size-[3px] rounded-full bg-white/30" />
              </div>
              <div className="relative">
                <Image
                  src={assets.macRecorder}
                  alt="BlitzRecorder recording studio on macOS"
                  priority
                  sizes="(min-width: 1024px) 620px, 100vw"
                  className="h-auto w-full rounded-[10px] ring-1 ring-white/5"
                />
                <WatchFilm />
              </div>
            </div>
          </div>
          <div className="relative mx-auto h-3 w-[104%] -translate-x-[2%] rounded-t-[2px] rounded-b-[12px] bg-gradient-to-b from-[#6a6a70] via-[#34343a] to-[#161618] shadow-[0_26px_34px_-22px_rgba(0,0,0,0.85)]">
            <div className="absolute left-1/2 top-0 h-[6px] w-[13%] -translate-x-1/2 rounded-b-[7px] bg-[#1b1b1e]" />
          </div>
        </div>

        {/* iPhone — feeds the Mac, so it sits in front of the window.
            Larger on phones (the viewer is holding one) and at right-0 so the
            rotated corner is not clipped by the page's overflow-x-hidden. */}
        <div
          className="absolute -bottom-9 right-0 w-[34%] min-w-[96px] max-w-[150px] sm:-bottom-8 sm:-right-6 sm:w-[27%]"
          style={{ animation: "br-float 7s ease-in-out infinite" }}
        >
          <div className="rotate-[5deg]">
            <div className="ring-gradient rounded-[26px] bg-muted/70 p-1.5 shadow-[0_30px_70px_-25px_rgba(0,0,0,0.95)] backdrop-blur-xl">
              <Image
                src={assets.iosPhone}
                alt="BlitzRecorder Camera app recording on iPhone"
                sizes="150px"
                className="h-auto w-full rounded-[20px]"
              />
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
}

function Features() {
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
        Every source,{" "}
        <span className="text-gradient">one recorder.</span>
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

function IphoneCompanion() {
  return (
    <Section
      id="iphone"
      className="grid items-center gap-12 py-20 lg:grid-cols-[0.85fr_1.15fr] lg:gap-20"
    >
      <JourneySectionView
        area="landing"
        section="iphone_companion"
        payload={{ page: "home" }}
      />
      <div data-reveal className="relative mx-auto">
        <div aria-hidden className="pointer-events-none absolute inset-0 -z-10">
          <div
            className="size-full"
            style={{
              background:
                "radial-gradient(50% 50% at 50% 45%, rgba(94,242,175,0.22), transparent 70%)",
            }}
          />
        </div>
        <div className="ring-gradient w-[min(320px,76vw)] rounded-[44px] bg-muted/70 p-3 shadow-[0_50px_110px_-45px_rgba(0,0,0,0.95)] backdrop-blur-xl">
          <Image
            src={assets.iosPhone}
            alt="BlitzRecorder Camera companion app on iPhone"
            sizes="320px"
            className="h-auto w-full rounded-[32px]"
          />
        </div>
      </div>
      <div>
        <div data-reveal>
          <Eyebrow>iPhone camera</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5 sm:text-5xl">
          Shot on the iPhone you already own.
        </Heading>
        <Paragraph data-reveal className="mt-6 max-w-xl">
          The iPhone records locally at full resolution, so quality never drops
          to a live video stream. When you stop, it hands the file off to your
          Mac automatically.
        </Paragraph>
        <ul data-reveal className="mt-8 flex flex-col gap-3.5 text-lg">
          <CheckItem>Records locally at full resolution</CheckItem>
          <CheckItem>Framed and controlled from your Mac</CheckItem>
          <CheckItem>Transfers to your Mac automatically</CheckItem>
        </ul>
      </div>
    </Section>
  );
}

/** Slim credibility row under the hero. Every claim here is literally true.
 *  TODO: add real beta-tester testimonials once collected — never fabricate. */
function TrustStrip() {
  const items = [
    "No account, ever",
    "Recordings stay on your Mac",
    "Pay once, no subscription",
    "30-day money-back guarantee",
    "From the makers of BlitzReels",
  ];
  return (
    <Section width="lg" className="pb-6 pt-0 sm:pb-10">
      <div
        data-reveal
        className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3"
      >
        {items.map((item) => (
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

function CompareCell({ on, highlight }: { on: boolean; highlight: boolean }) {
  return (
    <span className="flex justify-center">
      {on ? (
        <Check className={highlight ? "size-5 text-primary" : "size-5 text-muted-foreground"} />
      ) : (
        <Close className="size-4 text-faint" />
      )}
    </span>
  );
}

function Comparison() {
  return (
    <Section width="lg" className="py-24">
      <JourneySectionView
        area="landing"
        section="comparison"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>How it compares</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-3xl text-center">
        Sharper than Continuity Camera.{" "}
        <span className="text-gradient">Simpler than a subscription.</span>
      </Heading>
      <Paragraph data-reveal className="mx-auto mt-6 max-w-2xl text-center">
        The iPhone records your video at full quality, not a live stream, and
        you keep every raw file. No monthly fee for any of it.
      </Paragraph>
      <div data-reveal className="mx-auto mt-12 max-w-3xl overflow-x-auto">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr>
              <th className="w-1/2 py-3 pr-4" />
              {comparison.columns.map((col) => (
                <th
                  key={col.key}
                  className={
                    "px-3 py-3 text-center font-display text-[13px] font-bold sm:text-sm " +
                    (col.key === "blitz"
                      ? "rounded-t-xl bg-primary/[0.07] text-primary"
                      : "text-muted-foreground")
                  }
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {comparison.rows.map((row) => (
              <tr key={row.label} className="border-t border-border">
                <td className="py-3.5 pr-4 text-foreground">{row.label}</td>
                {comparison.columns.map((col) => (
                  <td
                    key={col.key}
                    className={
                      "px-3 py-3.5 " + (col.key === "blitz" ? "bg-primary/[0.07]" : "")
                    }
                  >
                    <CompareCell on={row[col.key]} highlight={col.key === "blitz"} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Section>
  );
}

function HowToStart() {
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

function Setups() {
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

function Pricing() {
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

function Faq() {
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

function ClosingCTA() {
  return (
    <Section width="sm" className="relative grid place-items-center py-28 text-center">
      <JourneySectionView
        area="landing"
        section="closing_cta"
        payload={{ page: "home" }}
      />
      <div aria-hidden className="pointer-events-none absolute inset-0 -z-10">
        <div
          className="mx-auto size-full max-w-2xl"
          style={{
            background:
              "radial-gradient(50% 50% at 50% 40%, rgba(94,242,175,0.16), transparent 70%)",
          }}
        />
      </div>
      <Image
        src={assets.macIcon}
        width={80}
        height={80}
        alt=""
        data-reveal
        className="rounded-[22%] shadow-[0_0_80px_-22px_rgba(94,242,175,0.95)]"
      />
      <Heading level={2} data-reveal className="mt-8">
        The studio camera is already in your pocket.
      </Heading>
        <Paragraph data-reveal className="mt-5">
          Pay once for the iPhone camera, 4K export, and 60 fps.
        </Paragraph>
      <div data-reveal className="mt-8 flex flex-wrap items-center justify-center gap-3">
        <BuyButton
          source="home_closing"
          className="h-12 rounded-full px-7 text-base shadow-[0_20px_60px_-22px_rgba(94,242,175,0.95)] transition-transform hover:scale-[1.03]"
        />
      </div>
      <a
        href={GITHUB_REPO_URL}
        target="_blank"
        rel="noopener"
        data-reveal
        onClick={() =>
          trackLandingCtaClicked({
            cta: "closing_github_repo",
            destination: GITHUB_REPO_URL,
          })
        }
        className="mt-5 inline-flex text-xs font-medium text-faint underline-offset-4 transition-colors hover:text-foreground hover:underline"
      >
        GitHub repo
      </a>
    </Section>
  );
}

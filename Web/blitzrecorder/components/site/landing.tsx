"use client";

import type { CSSProperties } from "react";
import Image from "next/image";
import { ArrowUpRight, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { SiteNav } from "@/components/site/site-nav";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteBackground } from "@/components/site/site-background";
import { CheckItem } from "@/components/site/check-item";
import { DownloadButton } from "@/components/site/download-button";
import { useRelease } from "@/components/site/release-context";
import { useReveal } from "@/components/site/use-reveal";
import { assets } from "@/lib/assets";
import {
  BLITZREELS_URL,
  cleanOutcomes,
  workflowCards,
  pricing,
  requirements,
  type Plan,
} from "@/lib/content";

/** Stagger a reveal; cast covers csstype not knowing CSS custom properties. */
const revealDelay = (ms: string): CSSProperties =>
  ({ "--reveal-delay": ms }) as CSSProperties;

export function Landing() {
  useReveal();
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <SiteBackground />
      <SiteNav />
      <main>
        <Hero />
        <CleanSources />
        <IphoneCompanion />
        <Workflow />
        <Pricing />
        <ClosingCTA />
      </main>
      <SiteFooter />
    </div>
  );
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
  const release = useRelease();
  return (
    <Section className="relative pt-32 pb-20 text-center sm:pt-40">
      <div data-reveal className="flex justify-center">
        <span className="glass ring-gradient inline-flex items-center gap-2.5 rounded-full px-4 py-1.5 text-sm text-muted-foreground">
          <span className="relative flex size-1.5">
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-primary opacity-75" />
            <span className="relative inline-flex size-1.5 rounded-full bg-primary" />
          </span>
          Beta for Mac creators
        </span>
      </div>

      <Heading
        level={1}
        data-reveal
        className="mx-auto mt-7 max-w-[15ch] text-5xl leading-[0.94] sm:text-7xl lg:text-[5.4rem]"
        style={revealDelay("60ms")}
      >
        Your iPhone is
        <br />
        <span className="text-gradient">your studio camera.</span>
      </Heading>
      <Paragraph
        data-reveal
        className="mx-auto mt-7 max-w-2xl text-balance sm:text-xl"
        style={revealDelay("120ms")}
      >
        It connects to your{" "}
        <span className="font-semibold whitespace-nowrap text-foreground">
          <AppleLogo className="mr-1.5 inline-block h-[0.85em] w-auto align-[-0.08em]" />
          Mac
        </span>{" "}
        and records locally on the phone, so your camera source stays sharp.
      </Paragraph>
      <div
        data-reveal
        className="mt-9 flex flex-wrap items-center justify-center gap-3"
        style={revealDelay("180ms")}
      >
        <DownloadButton className="h-12 rounded-full px-7 text-base shadow-[0_20px_60px_-22px_rgba(94,242,175,0.95)] transition-transform hover:scale-[1.03]" />
        <Button
          variant="outline"
          render={<a href="#how" />}
          className="h-12 rounded-full px-7 text-base"
        >
          See how it works
        </Button>
      </div>
      <Paragraph
        tone="faint"
        size="sm"
        className="mt-5"
        data-reveal
        style={revealDelay("240ms")}
      >
        {release
          ? `Free and open source · 10 free exports, then Pro · v${release.version}`
          : "Beta · 10 free exports · No card to start"}
      </Paragraph>

      <div
        data-reveal
        className="relative mx-auto mt-16 max-w-5xl"
        style={revealDelay("300ms")}
      >
        {/* emerald spotlight behind the app window */}
        <div aria-hidden className="pointer-events-none absolute -inset-x-12 -top-20 -bottom-8 -z-10">
          <div
            className="mx-auto h-full w-3/4"
            style={{
              background:
                "radial-gradient(50% 50% at 50% 45%, rgba(94,242,175,0.28), transparent 72%)",
            }}
          />
        </div>
        <div className="ring-gradient overflow-hidden rounded-2xl bg-card/40 p-1.5 shadow-[0_50px_120px_-40px_rgba(0,0,0,0.9)] backdrop-blur-xl">
          <Image
            src={assets.macRecorder}
            alt="BlitzRecorder recording studio on macOS"
            priority
            sizes="(min-width: 1024px) 1024px, 100vw"
            className="h-auto w-full rounded-xl"
          />
        </div>
      </div>
    </Section>
  );
}

function CleanSources() {
  return (
    <Section width="md" id="how" className="scroll-mt-24 py-28 text-center">
      <div data-reveal>
        <Eyebrow center>Choose the canvas before recording</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mt-5">
        One recording flow.
        <br />
        <span className="text-gradient">Shorts or long-form.</span>
      </Heading>
      <Paragraph data-reveal className="mx-auto mt-6 max-w-2xl">
        Pick a vertical or horizontal canvas, switch scenes while recording, and optionally keep source files when
        you want more control after the take.
      </Paragraph>
      <ul data-reveal className="mt-10 flex flex-wrap justify-center gap-2.5">
        {cleanOutcomes.map((outcome) => (
          <li key={outcome}>
            <Badge
              variant="secondary"
              className="glass ring-gradient h-9 gap-1.5 px-4 text-sm font-medium text-foreground"
            >
              <Check className="size-3.5 text-primary" />
              {outcome}
            </Badge>
          </li>
        ))}
      </ul>
    </Section>
  );
}

function IphoneCompanion() {
  return (
    <Section
      id="iphone"
      className="grid items-center gap-12 py-20 lg:grid-cols-[0.85fr_1.15fr] lg:gap-20"
    >
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
          <Eyebrow>iPhone companion</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5 sm:text-5xl">
          Record on the iPhone itself.
        </Heading>
        <Paragraph data-reveal className="mt-6 max-w-xl">
          BlitzRecorder records locally on your iPhone and saves the file to your Mac when you stop. You get
          a clean camera source from the phone you already own.
        </Paragraph>
        <ul data-reveal className="mt-8 flex flex-col gap-3.5 text-lg">
          <CheckItem>Records locally on your iPhone</CheckItem>
          <CheckItem>See and line up the shot from your Mac</CheckItem>
          <CheckItem>The video saves to your Mac on its own</CheckItem>
        </ul>
      </div>
    </Section>
  );
}

function Workflow() {
  return (
    <Section className="py-20">
      <div data-reveal className="flex justify-center">
        <Eyebrow center>Your workflow</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-3xl text-center">
        Fits the way you publish.
      </Heading>
      <div className="mt-14 grid gap-5 lg:grid-cols-3">
        {workflowCards.map((card, i) => (
          <Card
            key={card.title}
            data-reveal
            style={revealDelay(`${i * 110}ms`)}
            className="glass ring-gradient group/card gap-0 py-0 ring-0 transition-all duration-500 hover:-translate-y-1.5 hover:shadow-[0_40px_90px_-45px_rgba(94,242,175,0.5)]"
          >
            <div className="relative overflow-hidden">
              <span className="absolute left-4 top-4 z-[3] inline-flex size-8 items-center justify-center rounded-full bg-background/70 font-display text-sm font-bold text-primary ring-1 ring-primary/30 backdrop-blur-md">
                {String(i + 1).padStart(2, "0")}
              </span>
              <Image
                src={card.image}
                alt=""
                sizes="(min-width: 1024px) 380px, 100vw"
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
  const release = useRelease();
  return (
    <Section width="lg" id="pricing" className="scroll-mt-24 py-28">
      <div className="mx-auto max-w-2xl text-center">
        <div data-reveal className="flex justify-center">
          <Eyebrow center>Pricing</Eyebrow>
        </div>
        <Heading level={2} data-reveal className="mt-5">
          Start free. Upgrade when it&rsquo;s a habit.
        </Heading>
        <Paragraph data-reveal className="mt-5">
          The free trial gives you the whole app. Pro lets you save as many videos as you want.
        </Paragraph>
      </div>

      <div className="mx-auto mt-14 grid max-w-3xl gap-5 md:grid-cols-2">
        <div data-reveal>
          <PlanCard plan={pricing.trial} />
        </div>
        <div data-reveal style={revealDelay("110ms")}>
          <PlanCard plan={pricing.pro} featured />
        </div>
      </div>

      <Paragraph tone="faint" size="sm" className="mt-6 text-center" data-reveal>
        {release ? "Free and open source." : "Public beta. Access requests open soon."} Requires{" "}
        {requirements.macos}. The iPhone camera needs {requirements.ios}.
      </Paragraph>

      <div data-reveal>
        <BlitzReelsBanner />
      </div>
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
          <div className="flex items-center gap-3">
            <CardTitle className="font-display text-lg font-bold">{plan.name}</CardTitle>
            {featured ? <Badge>Recommended</Badge> : null}
          </div>
        </CardHeader>
        <CardContent className="flex flex-1 flex-col px-8">
          <p className="flex items-baseline gap-1.5 font-display tabular-nums">
            <span className="text-5xl font-black tracking-tight">{plan.price}</span>
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

          <DownloadButton
            variant={featured ? "default" : "outline"}
            className={
              "mt-8 h-12 w-full rounded-full text-base" +
              (featured ? " shadow-[0_20px_50px_-20px_rgba(94,242,175,0.9)]" : "")
            }
          />
        </CardContent>
      </Card>
    </div>
  );
}

function BlitzReelsBanner() {
  return (
    <Card className="glass ring-gradient mx-auto mt-5 max-w-3xl ring-0">
      <CardContent className="flex flex-col items-start justify-between gap-5 px-7 py-2 sm:flex-row sm:items-center">
        <div>
          <Image
            src={assets.blitzreelsWordmark}
            alt="BlitzReels"
            sizes="150px"
            className="h-6 w-auto"
          />
          <Paragraph size="base" className="mt-3">
            Have footage already? BlitzReels turns it into clips with captions.
          </Paragraph>
        </div>
        <Button
          variant="outline"
          render={<a href={BLITZREELS_URL} />}
          className="h-11 shrink-0 rounded-full border-primary/40 px-5 text-primary"
        >
          Turn my footage into clips
          <ArrowUpRight className="size-4" />
        </Button>
      </CardContent>
    </Card>
  );
}

function ClosingCTA() {
  return (
    <Section width="sm" className="relative grid place-items-center py-28 text-center">
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
        Start free. No card needed.
      </Paragraph>
      <div data-reveal className="mt-8 inline-flex">
        <DownloadButton className="h-12 rounded-full px-7 text-base shadow-[0_20px_60px_-22px_rgba(94,242,175,0.95)] transition-transform hover:scale-[1.03]" />
      </div>
    </Section>
  );
}

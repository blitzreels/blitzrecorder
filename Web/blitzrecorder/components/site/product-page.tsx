import Image from "next/image";
import type { StaticImageData } from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { ProductShell } from "@/components/site/product-shell";
import { CheckItem } from "@/components/site/check-item";
import { DownloadButton, VersionTag } from "@/components/site/download-button";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { pages, type ProductPageData, type ProductScreen } from "@/lib/content";

export function ProductPage({ variant }: { variant: "ios" | "macos" }) {
  const page = pages[variant];
  const other = variant === "ios" ? "macos" : "ios";
  // Only the Mac app ships a DMG; the iOS companion keeps the App Store CTA.
  const isMac = variant === "macos";
  return (
    <ProductShell>
      <main>
        <Hero page={page} isMac={isMac} />
        <CopyBlock page={page} />
        <Screens page={page} />
        <ClosingCTA page={page} other={other} isMac={isMac} />
      </main>
    </ProductShell>
  );
}

function Hero({ page, isMac }: { page: ProductPageData; isMac: boolean }) {
  return (
    <Section className="grid grid-cols-1 items-center gap-12 pt-28 pb-16 sm:pt-32 lg:grid-cols-[minmax(0,0.92fr)_minmax(420px,1fr)] lg:gap-16">
      <div className="min-w-0">
        <Image src={page.icon} width={56} height={56} alt="" className="rounded-[22%] shadow-2xl" />
        <Paragraph tone="faint" size="sm" className="mt-6 font-medium">
          {page.eyebrow}
        </Paragraph>
        <Heading level={1} className="mt-2 sm:text-6xl lg:text-7xl">
          {page.appName}
        </Heading>
        <Paragraph className="mt-6 max-w-xl sm:text-xl">{page.hero}</Paragraph>
        <div className="mt-8 flex flex-wrap items-center gap-3">
          {isMac ? (
            <DownloadButton className="h-12 rounded-full px-7 text-base" />
          ) : (
            <Button render={<Link href="/#pricing" />} className="h-12 rounded-full px-7 text-base">
              Request access
            </Button>
          )}
          <Button variant="outline" render={<Link href="/#how" />} className="h-12 rounded-full px-7 text-base">
            See how it works
          </Button>
        </div>
        <Paragraph tone="faint" size="sm" className="mt-5">
          {page.requirement}
        </Paragraph>
        {isMac ? (
          <VersionTag className="mt-2 inline-flex font-mono text-xs text-muted-foreground transition-colors hover:text-foreground" />
        ) : null}
      </div>
      <div className="grid min-w-0 place-items-center">
        {page.previewKind === "phone" ? <PhoneFrame src={page.preview} /> : <MacFrame src={page.preview} />}
      </div>
    </Section>
  );
}

function PhoneFrame({ src }: { src: StaticImageData }) {
  return (
    <div className="w-[min(330px,78vw)] rounded-[48px] border border-input bg-muted p-3 shadow-2xl">
      <Image src={src} alt="iPhone app preview" sizes="330px" className="h-auto w-full rounded-[36px]" />
    </div>
  );
}

function MacFrame({ src }: { src: StaticImageData }) {
  return (
    <Image
      src={src}
      alt="Mac app preview"
      sizes="(min-width: 1024px) 760px, 100vw"
      className="h-auto w-full max-w-[760px]"
    />
  );
}

function CopyBlock({ page }: { page: ProductPageData }) {
  return (
    <Section className="grid grid-cols-1 gap-10 border-t border-border py-20 md:grid-cols-[minmax(280px,0.85fr)_minmax(0,1fr)] lg:gap-20">
      <Heading level={2} className="sm:text-5xl">
        {page.copyTitle}
      </Heading>
      <div>
        <Paragraph>{page.copy}</Paragraph>
        <ul className="mt-8 flex flex-col gap-3.5 text-lg">
          {page.bullets.map((bullet) => (
            <CheckItem key={bullet}>{bullet}</CheckItem>
          ))}
        </ul>
      </div>
    </Section>
  );
}

function Screens({ page }: { page: ProductPageData }) {
  return (
    <Section className="border-t border-border py-20">
      <Heading level={2}>{page.screensTitle}</Heading>
      <div
        className={`mt-12 grid gap-5 ${
          page.screens.length === 4 ? "md:grid-cols-2 lg:grid-cols-4" : "md:grid-cols-2 lg:grid-cols-3"
        }`}
      >
        {page.screens.map((screen, index) => (
          <ScreenCard key={screen.title} screen={screen} index={index} />
        ))}
      </div>
    </Section>
  );
}

function ScreenCard({ screen, index }: { screen: ProductScreen; index: number }) {
  const imageClass =
    screen.kind === "icon"
      ? "mx-auto my-6 w-[min(180px,55%)] rounded-[24%] shadow-2xl"
      : screen.kind === "phone"
        ? "mx-auto mt-2 mb-5 w-[min(190px,calc(100%-48px))] rounded-[28px] border border-border"
        : "mx-4 mt-2 mb-4 w-[calc(100%-32px)] rounded-xl border border-border";

  return (
    <Card className="gap-0 overflow-hidden py-0 ring-border">
      <CardContent className="p-6 pb-2">
        <span className="font-mono text-sm font-semibold text-primary">{String(index + 1).padStart(2, "0")}</span>
        <Heading level={3} className="mt-3">
          {screen.title}
        </Heading>
        <Paragraph size="base" className="mt-2">
          {screen.text}
        </Paragraph>
      </CardContent>
      <Image src={screen.image} alt="" sizes="320px" className={`h-auto ${imageClass}`} />
    </Card>
  );
}

function ClosingCTA({
  page,
  other,
  isMac,
}: {
  page: ProductPageData;
  other: "ios" | "macos";
  isMac: boolean;
}) {
  const otherLabel = other === "ios" ? "the iPhone camera app" : "the Mac app";
  return (
    <Section width="sm" className="grid place-items-center border-t border-border py-24 text-center">
      <Image
        src={page.icon}
        width={72}
        height={72}
        alt=""
        className="rounded-[22%] shadow-[0_0_70px_-26px_rgba(94,242,175,0.9)]"
      />
      <Heading level={2} className="mt-7 leading-[1.04] sm:text-5xl">
        Start recording in studio quality.
      </Heading>
      <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
        {isMac ? (
          <DownloadButton className="h-12 rounded-full px-7 text-base" />
        ) : (
          <Button render={<Link href="/#pricing" />} className="h-12 rounded-full px-7 text-base">
            Request access
          </Button>
        )}
        <Button
          variant="outline"
          render={<Link href={`/${other}`} />}
          className="h-12 rounded-full px-6 text-base"
        >
          Get {otherLabel}
          <ArrowUpRight className="size-4" />
        </Button>
      </div>
    </Section>
  );
}

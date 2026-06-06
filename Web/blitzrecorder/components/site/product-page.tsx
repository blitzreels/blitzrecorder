import Image from "next/image";
import type { StaticImageData } from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "@/components/site/icons";
import { ProductShell } from "@/components/site/product-shell";
import { CheckItem } from "@/components/site/check-item";
import { DownloadButton, DownloadMeta } from "@/components/site/download-button";
import {
  JourneyPageView,
  JourneySectionView,
} from "@/components/site/journey-markers";
import { TrackedLinkButton } from "@/components/site/tracked-link-button";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { pages, type ProductPageData, type ProductScreen } from "@/lib/content";

const IOS_BETA_HREF =
  "mailto:support@blitzreels.com?subject=Join%20the%20BlitzRecorder%20Camera%20beta";

export function ProductPage({ variant }: { variant: "ios" | "macos" }) {
  const page = pages[variant];
  const other = variant === "ios" ? "macos" : "ios";
  // Only the Mac app ships a DMG; the iOS companion keeps the App Store CTA.
  const isMac = variant === "macos";
  return (
    <ProductShell>
      <JourneyPageView
        area="product"
        eventName="product_page_viewed"
        payload={{
          page: variant,
        }}
      />
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
      <JourneySectionView
        area="product"
        section="hero"
        payload={{ page: page.key }}
      />
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
            <DownloadButton
              source="product_macos_hero"
              className="h-12 rounded-full px-7 text-base"
            />
          ) : (
            <TrackedLinkButton
              href={IOS_BETA_HREF}
              label="Join iPhone beta"
              className="h-12 rounded-full px-7 text-base"
              area="product"
              eventName="product_cta_clicked"
              payload={{ page: page.key, cta: "join_iphone_beta" }}
            />
          )}
          <TrackedLinkButton
            href="/#how"
            label="See how it works"
            variant="outline"
            className="h-12 rounded-full px-7 text-base"
            area="product"
            eventName="product_cta_clicked"
            payload={{ page: page.key, cta: "see_how" }}
          />
        </div>
        {isMac ? (
          <DownloadMeta className="mt-5 text-sm" />
        ) : (
          <Paragraph tone="faint" size="sm" className="mt-5">
            {page.requirement} · beta access by email
          </Paragraph>
        )}
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
      <JourneySectionView
        area="product"
        section="copy"
        payload={{ page: page.key }}
      />
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
      <JourneySectionView
        area="product"
        section="screens"
        payload={{ page: page.key }}
      />
      <Heading level={2}>{page.screensTitle}</Heading>
      <div className="mt-16 flex flex-col gap-20 lg:gap-24">
        {page.screens.map((screen, index) => (
          <ScreenRow key={screen.title} screen={screen} index={index} />
        ))}
      </div>
    </Section>
  );
}

/** One step per row: copy on one side, a properly sized visual on the other. */
function ScreenRow({ screen, index }: { screen: ProductScreen; index: number }) {
  const reversed = index % 2 === 1;
  return (
    <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
      <div className={reversed ? "lg:order-2" : undefined}>
        <span className="font-mono text-sm font-semibold text-primary">
          {String(index + 1).padStart(2, "0")}
        </span>
        <Heading level={3} className="mt-3 text-2xl sm:text-3xl">
          {screen.title}
        </Heading>
        <Paragraph className="mt-4 max-w-md">{screen.text}</Paragraph>
      </div>
      <div className={`grid place-items-center ${reversed ? "lg:order-1" : ""}`}>
        <ScreenVisual screen={screen} />
      </div>
    </div>
  );
}

function ScreenVisual({ screen }: { screen: ProductScreen }) {
  if (screen.kind === "icon") {
    return (
      <Image
        src={screen.image}
        alt=""
        sizes="220px"
        className="my-6 w-[min(220px,55vw)] rounded-[24%] shadow-[0_0_90px_-25px_rgba(94,242,175,0.8)]"
      />
    );
  }
  if (screen.kind === "phone") {
    return (
      <div className="w-[min(290px,72vw)] rounded-[44px] border border-input bg-muted p-3 shadow-2xl">
        <Image src={screen.image} alt="" sizes="290px" className="h-auto w-full rounded-[34px]" />
      </div>
    );
  }
  return (
    <Image
      src={screen.image}
      alt=""
      sizes="(min-width: 1024px) 560px, 100vw"
      className="h-auto w-full max-w-[560px] rounded-xl border border-border shadow-2xl"
    />
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
          <DownloadButton
            source="product_macos_closing"
            className="h-12 rounded-full px-7 text-base"
          />
        ) : (
          <TrackedLinkButton
            href={IOS_BETA_HREF}
            label="Join iPhone beta"
            className="h-12 rounded-full px-7 text-base"
            area="product"
            eventName="product_cta_clicked"
            payload={{ page: page.key, cta: "closing_join_iphone_beta" }}
          />
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

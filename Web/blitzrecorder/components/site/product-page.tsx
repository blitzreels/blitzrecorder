import Image from "next/image";
import Link from "next/link";
import { ArrowRight } from "@/components/site/icons";
import { AppWindow } from "@/components/site/app-window";
import { ProductShell } from "@/components/site/product-shell";
import { DownloadButton, DownloadMeta } from "@/components/site/download-button";
import { JourneyPageView, JourneySectionView } from "@/components/site/journey-markers";
import { NotifyForm } from "@/components/site/notify-form";
import { Check } from "@/components/site/icons";
import { Phone } from "@/components/site/landing/camera-chapter";
import { ChapterRuler } from "@/components/site/landing/chapter";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { pages, type ProductPageData } from "@/lib/content";

export function ProductPage({ variant }: { variant: "ios" | "macos" }) {
  const page = pages[variant];
  const other = variant === "ios" ? pages.macos : pages.ios;
  const isMac = variant === "macos";
  return (
    <ProductShell>
      <JourneyPageView area="product" eventName="product_page_viewed" payload={{ page: variant }} />
      <main>
        <Hero page={page} isMac={isMac} />
        <CopyBlock page={page} />
        <Steps page={page} />
        <ClosingCTA page={page} other={other} isMac={isMac} />
      </main>
    </ProductShell>
  );
}

function PrimaryAction({ page, isMac, placement }: { page: ProductPageData; isMac: boolean; placement: "hero" | "closing" }) {
  if (isMac) {
    return <DownloadButton source={`product_macos_${placement}`} size="lg" label="Download for Mac" className="" />;
  }
  return (
    <NotifyForm
      source={`ios_beta_${placement}`}
      cta="Join the waitlist"
      success={`You're on the list for ${page.appName}.`}
    />
  );
}

function Hero({ page, isMac }: { page: ProductPageData; isMac: boolean }) {
  return (
    <Section className="grid items-center gap-14 pt-32 pb-20 sm:pt-40 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:gap-14">
      <JourneySectionView area="product" section="hero" payload={{ page: page.key }} />
      <div className="min-w-0">
        <div className="flex items-center gap-3">
          <Image src={page.icon} width={44} height={44} alt="" className="rounded-[22%]" />
          <span className="label-mono text-muted-foreground">{page.appName}</span>
        </div>
        <Heading level={1} className="mt-8 max-w-[12ch] text-[clamp(2.75rem,6.5vw,4.75rem)] leading-[0.95]">
          {page.tagline}.
        </Heading>
        <Paragraph className="mt-6 max-w-lg sm:text-xl sm:leading-8">{page.hero}</Paragraph>
        <div className="mt-9">
          <PrimaryAction page={page} isMac={isMac} placement="hero" />
        </div>
        {isMac ? (
          <DownloadMeta className="mt-4 text-sm" compact={false} align="start" />
        ) : (
          <p className="mt-4 text-sm text-faint">{page.requirement} · coming to the App Store</p>
        )}
      </div>
      <div className="min-w-0">
        {isMac ? (
          <AppWindow className="max-sm:rounded-tile">
            <Image
              src={assets.editor}
              alt="The BlitzRecorder editor on macOS"
              priority
              sizes="(min-width: 1024px) 760px, 100vw"
              className="h-auto w-full max-sm:w-[190%] max-sm:max-w-none max-sm:-translate-x-[23%]"
            />
          </AppWindow>
        ) : (
          <div className="app-surface grid place-items-center rounded-card bg-background py-14">
            <Phone className="w-[210px]" />
          </div>
        )}
      </div>
    </Section>
  );
}

function CopyBlock({ page }: { page: ProductPageData }) {
  return (
    <Section className="py-20 sm:py-28">
      <JourneySectionView area="product" section="copy" payload={{ page: page.key }} />
      <ChapterRuler mark={{ time: "00:00", name: page.eyebrow }} />
      <div className="mt-12 grid gap-10 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] lg:gap-20">
        <Heading level={2} className="max-w-[16ch]">
          {page.copyTitle}
        </Heading>
        <div>
          <Paragraph>{page.copy}</Paragraph>
          <ul className="mt-8 flex flex-col">
            {page.bullets.map((bullet) => (
              <li key={bullet} className="flex items-start gap-3 border-t border-separator py-3.5">
                <Check className="mt-1 size-4 shrink-0 text-primary" strokeWidth={2.5} />
                <span>{bullet}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </Section>
  );
}

function Steps({ page }: { page: ProductPageData }) {
  return (
    <Section className="pb-24 sm:pb-32">
      <JourneySectionView area="product" section="screens" payload={{ page: page.key }} />
      <p className="label-mono text-faint">{page.screensTitle}</p>
      <ol className={`mt-6 grid gap-x-8 sm:grid-cols-2 ${page.screens.length === 3 ? "lg:grid-cols-3" : "lg:grid-cols-4"}`}>
        {page.screens.map((screen, index) => (
          <li key={screen.title} className="border-t border-separator pt-6 pb-8">
            <span className="label-mono text-primary">{String(index + 1).padStart(2, "0")}</span>
            <h3 className="mt-4 font-display text-xl font-bold tracking-[-0.02em]">{screen.title}</h3>
            <p className="mt-2 text-[15px] leading-6 text-muted-foreground">{screen.text}</p>
          </li>
        ))}
      </ol>
    </Section>
  );
}

function ClosingCTA({ page, other, isMac }: { page: ProductPageData; other: ProductPageData; isMac: boolean }) {
  return (
    <Section className="grid place-items-center border-t border-separator py-28 text-center">
      <Image
        src={page.icon}
        width={80}
        height={80}
        alt=""
        className="rounded-[22%]"
      />
      <Heading level={2} className="mt-8 max-w-[14ch]">
        {isMac ? "Record your next video today." : "Get the iPhone app first."}
      </Heading>
      <div className="mt-9">
        <PrimaryAction page={page} isMac={isMac} placement="closing" />
      </div>
      <Link
        href={`/${other.key}`}
        className="group mt-6 inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
      >
        {other.key === "ios" ? "See the iPhone camera app" : "See the Mac app"}
        <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
      </Link>
    </Section>
  );
}

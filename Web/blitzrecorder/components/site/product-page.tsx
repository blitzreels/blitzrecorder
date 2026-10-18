import Image from "next/image";
import Link from "next/link";
import { ProductShell } from "@/components/site/product-shell";
import { DownloadButton, DownloadMeta } from "@/components/site/download-button";
import { JourneyPageView, JourneySectionView } from "@/components/site/journey-markers";
import { NotifyForm } from "@/components/site/notify-form";
import { Check } from "@/components/site/icons";
import { StepList } from "@/components/site/step-list";
import { Phone } from "@/components/site/landing/camera-chapter";
import { Section } from "@/components/ui/layout";
import { StudioMockup } from "@/components/site/studio-mockup";
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
    return <DownloadButton source={`product_macos_${placement}`} size="lg" label="Download free for Mac" className="" />;
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
    <Section width="page" className="pt-32 pb-24 sm:pt-40 sm:pb-32">
      <JourneySectionView area="product" section="hero" payload={{ page: page.key }} />
      <div className="mx-auto flex max-w-[46rem] flex-col items-center text-center">
        <Image src={page.icon} width={72} height={72} alt="" className="size-16 rounded-[22.5%] sm:size-[72px]" />
        <h1 className="type-hero mt-8 text-[clamp(2.75rem,6vw,5rem)]">{page.tagline}.</h1>
        <p className="mt-6 max-w-[40ch] text-lg leading-7 text-pretty text-muted-foreground sm:text-xl sm:leading-8">
          {page.hero}
        </p>
        <div className="mt-9">
          <PrimaryAction page={page} isMac={isMac} placement="hero" />
        </div>
        {isMac ? (
          <DownloadMeta className="mt-4 text-sm" compact={false} align="center" />
        ) : (
          <p className="mt-4 text-sm text-faint">{page.requirement}. Coming to the App Store.</p>
        )}
      </div>

      <div className="mt-16 sm:mt-24">
        {isMac ? (
          <StudioMockup className="mx-auto w-full" priority />
        ) : (
          <div className="grid place-items-center">
            <Phone className="w-[min(280px,68vw)]" />
          </div>
        )}
      </div>
    </Section>
  );
}

function CopyBlock({ page }: { page: ProductPageData }) {
  return (
    <Section width="page" className="py-24 sm:py-32">
      <JourneySectionView area="product" section="copy" payload={{ page: page.key }} />
      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-24">
        <h2 className="type-title max-w-[16ch] text-[clamp(2.25rem,4.4vw,3.75rem)]">{page.copyTitle}</h2>
        <div>
          <p className="text-lg leading-8 text-pretty text-muted-foreground">{page.copy}</p>
          <ul className="mt-8 flex flex-col gap-3.5">
            {page.bullets.map((bullet) => (
              <li key={bullet} className="flex items-start gap-3 text-[15px] leading-6">
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
    <Section width="page" className="py-24 sm:py-32">
      <JourneySectionView area="product" section="screens" payload={{ page: page.key }} />
      <h2 className="type-title text-[clamp(2.25rem,4.4vw,3.75rem)]">{page.screensTitle}</h2>
      <div className="mt-14">
        <StepList steps={page.screens} />
      </div>
    </Section>
  );
}

function ClosingCTA({ page, other, isMac }: { page: ProductPageData; other: ProductPageData; isMac: boolean }) {
  return (
    <Section width="page" className="flex flex-col items-center pt-16 pb-32 text-center sm:pb-40">
      <Image src={page.icon} width={80} height={80} alt="" className="size-20 rounded-[22.5%]" />
      <h2 className="type-hero mt-8 max-w-[14ch] text-[clamp(2.5rem,5.6vw,4.75rem)]">
        {isMac ? "Record your next video today." : "Get the iPhone app first."}
      </h2>
      <div className="mt-10">
        <PrimaryAction page={page} isMac={isMac} placement="closing" />
      </div>
      <Link
        href={`/${other.key}`}
        className="mt-6 text-sm font-medium text-muted-foreground underline decoration-white/20 underline-offset-4 transition-colors hover:text-foreground hover:decoration-white"
      >
        {other.key === "ios" ? "See the iPhone camera app" : "See the Mac app"}
      </Link>
    </Section>
  );
}

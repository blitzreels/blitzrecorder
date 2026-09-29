import Image from "next/image";
import { ChevronDown } from "@/components/site/icons";
import { AppWindow } from "@/components/site/app-window";
import { DownloadButton, DownloadMeta } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { revealDelay } from "@/components/site/landing/reveal";
import { trackLandingCtaClicked } from "@/components/site/landing/tracking";
import { assets } from "@/lib/assets";

export function Hero() {
  return (
    <div>
      <Section className="pt-32 text-center sm:pt-40">
        <JourneySectionView area="landing" section="hero" payload={{ page: "home" }} />

        <Heading
          level={1}
          data-reveal
          className="mx-auto max-w-[12ch] text-[clamp(2.5rem,6vw,4.75rem)] leading-[0.95] sm:max-w-none"
        >
          Record and edit videos <br className="hidden sm:block" />
          <span className="text-primary">on your Mac.</span>
        </Heading>

        <Paragraph
          data-reveal
          className="mx-auto mt-6 max-w-[32rem] text-balance sm:text-xl sm:leading-8"
          style={revealDelay("80ms")}
        >
          Capture your screen and camera in one take, then cut it on a timeline.
          Free and open source.
        </Paragraph>

        <div
          data-reveal
          className="mt-9 flex flex-col items-center gap-4 sm:flex-row sm:justify-center sm:gap-6"
          style={revealDelay("160ms")}
        >
          <DownloadButton source="home_hero" size="lg" label="Download for Mac" className="" />
          <a
            href="#record"
            onClick={() => trackLandingCtaClicked({ cta: "hero_see_how", destination: "#record" })}
            className="inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            See how it works
            <ChevronDown className="size-4" />
          </a>
        </div>

        <div data-reveal className="mt-5" style={revealDelay("200ms")}>
          <DownloadMeta compact className="text-sm" align="center" />
        </div>
      </Section>

      <div
        data-reveal
        style={revealDelay("240ms")}
        className="mx-auto mt-16 w-[min(1180px,calc(100%-24px))] sm:mt-20 sm:w-[min(1180px,calc(100%-48px))]"
      >
        <AppWindow className="max-sm:rounded-tile">
          <Image
            src={assets.editor}
            alt="The BlitzRecorder editor with a vertical screen and camera split, and screen, camera, mic, and Mac audio tracks on the timeline"
            priority
            sizes="(min-width: 1280px) 1180px, 100vw"
            className="h-auto w-full max-sm:w-[190%] max-sm:max-w-none max-sm:-translate-x-[23%]"
          />
        </AppWindow>
      </div>
    </div>
  );
}

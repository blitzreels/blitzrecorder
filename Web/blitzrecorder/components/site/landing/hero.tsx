import Image from "next/image";
import { ChevronDown } from "@/components/site/icons";
import { WatchFilm } from "@/components/site/watch-film";
import { DownloadButton, DownloadMeta } from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { AppleLogo } from "@/components/site/landing/apple-logo";
import { revealDelay } from "@/components/site/landing/reveal";
import { trackLandingCtaClicked } from "@/components/site/landing/tracking";

export function Hero() {
  return (
    <Section className="relative grid items-center gap-9 pt-24 pb-24 sm:gap-14 sm:pt-40 xl:grid-cols-[1fr_1.18fr] xl:gap-12">
      <JourneySectionView
        area="landing"
        section="hero"
        payload={{ page: "home" }}
      />
      <div className="text-center xl:text-left">
        <Heading
          level={1}
          data-reveal
          className="mx-auto max-w-[16ch] text-[clamp(2.25rem,14vw_-_8px,3rem)] leading-[0.94] sm:text-7xl xl:mx-0 xl:text-[4.4rem]"
          style={revealDelay("60ms")}
        >
          Record the screen.
          <br />
          <span className="text-gradient">Cut the short.</span>
        </Heading>
        <Paragraph
          data-reveal
          className="mx-auto mt-5 max-w-xl text-balance sm:mt-6 sm:text-xl xl:mx-0"
          style={revealDelay("120ms")}
        >
          Native{" "}
          <span className="font-semibold whitespace-nowrap text-foreground">
            <AppleLogo className="mr-1.5 inline-block h-[0.85em] w-auto align-[-0.08em]" />
            macOS
          </span>{" "}
          screen recorder for short-form. Timeline and silence cuts in the same
          app.
        </Paragraph>
        <div
          data-reveal
          className="mt-7 flex flex-col items-center gap-3 min-[480px]:flex-row min-[480px]:flex-wrap min-[480px]:justify-center sm:mt-8 xl:justify-start"
          style={revealDelay("180ms")}
        >
          <DownloadButton
            source="home_hero"
            className="h-12 w-full max-w-80 rounded-full px-7 text-base min-[480px]:w-auto"
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
            What&apos;s in the app
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
            What&apos;s in the app
            <ChevronDown className="size-4" />
          </a>
        </div>
        <div data-reveal className="mt-4 sm:mt-5" style={revealDelay("240ms")}>
          <DownloadMeta compact className="text-sm" />
        </div>
      </div>

      <div
        data-reveal
        className="relative mx-auto w-full max-w-xl xl:max-w-none"
        style={revealDelay("220ms")}
      >
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
                  alt="BlitzRecorder screen recording studio on macOS"
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
      </div>
    </Section>
  );
}

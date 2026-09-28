import Image from "next/image";
import { ArrowRight, ChevronDown } from "@/components/site/icons";
import { AppWindow } from "@/components/site/app-window";
import {
  DownloadButton,
  DownloadMeta,
  GitHubMark,
} from "@/components/site/download-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { useRelease } from "@/components/site/release-context";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { chapters } from "@/components/site/landing/chapter";
import { revealDelay } from "@/components/site/landing/reveal";
import { trackLandingCtaClicked } from "@/components/site/landing/tracking";
import { assets } from "@/lib/assets";
import { FALLBACK_VERSION, GITHUB_REPO_URL, RELEASES_URL } from "@/lib/release";

const chapterLinks = [
  { mark: chapters.record, href: "#record" },
  { mark: chapters.camera, href: "#camera" },
  { mark: chapters.edit, href: "#edit" },
  { mark: chapters.export, href: "#export" },
];

export function Hero() {
  const release = useRelease();
  const version = release?.version ?? FALLBACK_VERSION;
  const minor = version.split(".").slice(0, 2).join(".");

  return (
    <div className="relative">
      <Section className="relative pt-28 text-center sm:pt-36">
        <JourneySectionView area="landing" section="hero" payload={{ page: "home" }} />
        <a
          data-reveal
          href={release?.htmlUrl ?? RELEASES_URL}
          target="_blank"
          rel="noopener"
          onClick={() => trackLandingCtaClicked({ cta: "hero_release", destination: "release_notes" })}
          className="group inline-flex h-8 items-center gap-2.5 rounded-control bg-fill-control pr-3 pl-1 text-[13px] text-muted-foreground transition-colors hover:bg-fill-hover hover:text-foreground"
        >
          <span className="rounded-inner bg-primary/15 px-1.5 py-0.5 font-mono text-xs font-semibold text-primary">
            v{minor}
          </span>
          <span className="hidden min-[400px]:inline">Transcripts, faster exports, Send to BlitzReels</span>
          <span className="min-[400px]:hidden">What&apos;s new</span>
          <ArrowRight className="size-3.5 transition-transform group-hover:translate-x-0.5" />
        </a>

        <Heading level={1} data-reveal className="mx-auto mt-7 max-w-[11ch] sm:mt-8" style={revealDelay("60ms")}>
          Your next video <span className="text-primary">starts here.</span>
        </Heading>

        <Paragraph
          data-reveal
          className="mx-auto mt-6 max-w-[30rem] text-balance sm:mt-7 sm:text-xl sm:leading-8"
          style={revealDelay("120ms")}
        >
          Record your screen and camera, then edit the take on your Mac.
          Free, open source, and fully local.
        </Paragraph>

        <div
          data-reveal
          className="mt-8 flex flex-col items-center gap-3 min-[480px]:flex-row min-[480px]:justify-center"
          style={revealDelay("180ms")}
        >
          <DownloadButton
            source="home_hero"
            size="lg"
            label="Download for Mac"
            className="w-full max-w-80 min-[480px]:w-auto"
          />
          <Button
            variant="outline"
            size="lg"
            render={<a href={GITHUB_REPO_URL} target="_blank" rel="noopener" />}
            onClick={() => trackLandingCtaClicked({ cta: "hero_github", destination: GITHUB_REPO_URL })}
            className="hidden min-[480px]:inline-flex"
          >
            <GitHubMark className="size-4" />
            View the source
          </Button>
          <a
            href="#record"
            onClick={() => trackLandingCtaClicked({ cta: "hero_see_how_mobile", destination: "#record" })}
            className="inline-flex items-center gap-1.5 py-1 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground min-[480px]:hidden"
          >
            See how it works
            <ChevronDown className="size-4" />
          </a>
        </div>

        <div data-reveal className="mt-4" style={revealDelay("220ms")}>
          <DownloadMeta compact className="text-sm" align="center" />
        </div>
      </Section>

      <div className="relative mt-14 sm:mt-20">
        <div
          data-reveal
          style={revealDelay("260ms")}
          className="relative mx-auto w-[min(1240px,calc(100%-24px))] sm:w-[min(1240px,calc(100%-48px))]"
        >
          <AppWindow className="max-sm:rounded-tile">
            <Image
              src={assets.editor}
              alt="The BlitzRecorder editor with a vertical screen and camera split, and screen, camera, mic, and Mac audio tracks on the timeline"
              priority
              sizes="(min-width: 1280px) 1240px, 100vw"
              className="h-auto w-full max-sm:w-[190%] max-sm:max-w-none max-sm:-translate-x-[23%]"
            />
          </AppWindow>
        </div>
      </div>

      <Section className="relative mt-6 flex flex-col gap-4 sm:mt-8 md:flex-row md:items-center md:justify-between">
        <p className="label-mono text-center text-faint md:text-left">Real capture · BlitzRecorder {minor} editor</p>
        <nav aria-label="Chapters" className="hidden flex-wrap gap-x-6 gap-y-2 md:flex">
          {chapterLinks.map(({ mark, href }) => (
            <a
              key={href}
              href={href}
              className="group inline-flex items-baseline gap-2 transition-colors"
            >
              <span className="label-mono text-primary/80 group-hover:text-primary">{mark.time}</span>
              <span className="text-sm text-muted-foreground group-hover:text-foreground">{mark.name}</span>
            </a>
          ))}
        </nav>
      </Section>
    </div>
  );
}

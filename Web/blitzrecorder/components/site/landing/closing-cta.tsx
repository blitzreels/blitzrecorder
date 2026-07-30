import Image from "next/image";
import { BuyButton } from "@/components/site/buy-button";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { assets } from "@/lib/assets";
import { GITHUB_REPO_URL } from "@/lib/release";
import { trackLandingCtaClicked } from "@/components/site/landing/tracking";

export function ClosingCTA() {
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

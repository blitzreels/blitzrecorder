import type { ReactNode } from "react";
import { GitHubMark } from "@/components/site/download-button";
import { Check } from "@/components/site/icons";
import { GetApp } from "@/components/site/landing/get-app";
import { LandingSection } from "@/components/site/landing/landing-section";
import { GITHUB_REPO_URL } from "@/lib/release";
import { cn } from "@/lib/utils";

const appIncludes = [
  "Screen and camera in one take",
  "Vertical, landscape and square from one recording",
  "Pauses cut in one click",
  "4K export with no watermark",
  "Updates itself",
];

const hostingIncludes = [
  "Share a link instead of sending a file",
  "50 GB of storage and 5 hours of uploads a month",
  "Cancel from the app",
];

export function Pricing() {
  return (
    <LandingSection
      id="free"
      section="license"
      title="Make every video for free."
      intro="The whole app is free and open source. Pay only if you want us to host your share links."
      action={null}
    >
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]">
        <PricePanel price="Free" name="The app, with every feature" items={appIncludes} highlight action={<>
          <GetApp source="home_free_app" align="start" />
          <a
            href={GITHUB_REPO_URL}
            target="_blank"
            rel="noopener"
            className="mt-6 inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            <GitHubMark className="size-4" />
            Read the code on GitHub
          </a>
        </>} />
        <PricePanel price="€9" name="A month for hosting, if you want it" items={hostingIncludes}
          highlight={false} action={null} />
      </div>
    </LandingSection>
  );
}

function PricePanel({ price, name, items, highlight, action }: {
  price: string;
  name: string;
  items: string[];
  highlight: boolean;
  action: ReactNode | null;
}) {
  return (
    <div className="product-surface flex flex-col rounded-card p-7 sm:p-10">
      <p className={cn("type-hero text-[clamp(4rem,8vw,6rem)] leading-none", highlight ? "text-primary" : "text-foreground")}>
        {price}
      </p>
      <p className="mt-4 text-lg font-medium text-pretty">{name}</p>
      <ul className="mt-7 flex flex-col gap-3.5">
        {items.map((item) => (
          <li key={item} className="flex items-start gap-3 text-[15px] leading-6 text-muted-foreground">
            <Check className={cn("mt-1 size-4 shrink-0", highlight ? "text-primary" : "text-faint")} strokeWidth={2.5} />
            <span>{item}</span>
          </li>
        ))}
      </ul>
      {action ? <div className="mt-10">{action}</div> : null}
    </div>
  );
}

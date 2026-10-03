import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { NavItem, SiteHeader } from "@/components/site/site-header";
import { videosPath } from "@/lib/hosting/paths";
import { viewerAccount } from "@/lib/hosting/web-session";
import { SignInForm } from "./sign-in-form";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Sign in — BlitzRecorder", robots: { index: false, follow: false }, referrer: "no-referrer",
};

const SHARE_PATH = /^\/s\/[A-Za-z0-9_-]{24}$/;

/** Only a share page is a valid return target, so `next` can never become an open redirect. */
function returnPath(next: string | undefined) {
  return next && SHARE_PATH.test(next) ? next : videosPath;
}

export default async function HostingSignIn({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true" && process.env.NODE_ENV === "production") redirect(videosPath);
  const next = returnPath((await searchParams).next);
  if (process.env.BLITZRECORDER_HOSTING_ENABLED === "true" && await viewerAccount()) redirect(next);
  const fromVideo = SHARE_PATH.test(next);
  const library = process.env.NODE_ENV === "development" && process.env.BLITZRECORDER_HOSTING_ENABLED !== "true"
    ? "/videos/preview" : videosPath;

  return <main className="flex min-h-screen flex-col bg-background text-foreground">
    <SiteHeader
      innerClassName="max-w-[1480px] px-4 sm:px-6"
      nav={<nav aria-label="Account">
        <NavItem href={fromVideo ? next : library}>{fromVideo ? "Back to video" : "Videos"}</NavItem>
      </nav>}
    />
    <section className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center px-4 pb-[14vh]">
      <SignInForm next={next} intro={fromVideo
        ? "Sign in to browse all your shared videos next to this one."
        : "Sign in to see the videos you’ve shared from BlitzRecorder."} />
    </section>
  </main>;
}

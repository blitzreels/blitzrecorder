import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { SiteMark } from "@/components/hosting/status-screen";
import { viewerAccount } from "@/lib/hosting/web-session";
import { SignInForm } from "./sign-in-form";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Sign in — BlitzRecorder", robots: { index: false, follow: false }, referrer: "no-referrer",
};

const SHARE_PATH = /^\/s\/[A-Za-z0-9_-]{24}$/;

/** Only share pages and the library are valid return targets, so `next` can never become an open redirect. */
function returnPath(next: string | undefined) {
  return next && (SHARE_PATH.test(next) || next === "/hosting/videos") ? next : "/hosting/videos";
}

export default async function HostingSignIn({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") redirect("/hosting/videos");
  const next = returnPath((await searchParams).next);
  if (await viewerAccount()) redirect(next);
  const fromVideo = SHARE_PATH.test(next);

  return <main className="flex min-h-screen flex-col bg-background px-4 text-foreground sm:px-6">
    <header className="mx-auto flex h-16 w-full max-w-[1480px] items-center justify-between">
      <SiteMark />
      {fromVideo && <Link href={next} className="inline-flex items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground">
        <ArrowLeft className="size-4" /> Back to video
      </Link>}
    </header>
    <section className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center pb-[14vh]">
      <SignInForm next={next} intro={fromVideo
        ? "Sign in to browse all your shared videos next to this one."
        : "Sign in to see the videos you’ve shared from BlitzRecorder."} />
    </section>
  </main>;
}

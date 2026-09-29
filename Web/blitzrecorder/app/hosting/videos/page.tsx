import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { CreditCard, Film, LoaderCircle, RotateCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SignOutButton, SignOutEverywhere } from "@/components/hosting/sign-out-button";
import { StatusScreen } from "@/components/hosting/status-screen";
import { accountState, activeSessionCount } from "@/lib/hosting/account";
import { HOSTING_PLAN } from "@/lib/hosting/plan";
import { hostingStanding, ownerLibrary, viewerAccount } from "@/lib/hosting/web-session";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Your videos — BlitzRecorder", robots: { index: false, follow: false } };

export default async function HostingVideos() {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") {
    return <StatusScreen icon={<Film />} title="Video sharing isn’t available yet"
      actions={<Button variant="outline" render={<Link href="/" />}>Go to BlitzRecorder</Button>}>
      Your recordings stay on your Mac. Sharing links will open here once hosting launches.
    </StatusScreen>;
  }
  const account = await viewerAccount();
  if (!account) redirect("/hosting/sign-in");
  const [standing, sessions] = await Promise.all([
    accountState(account).active ? null : hostingStanding(account), activeSessionCount(account),
  ]);
  const accountFooter = <span className="inline-flex flex-wrap items-center justify-center gap-x-2 gap-y-1">
    <span>{account.email}</span>
    <span aria-hidden>·</span>
    <SignOutButton className="text-xs text-faint underline-offset-4 transition-colors hover:text-foreground hover:underline disabled:opacity-60" />
    {sessions > 1 && <><span aria-hidden>·</span><SignOutEverywhere sessions={sessions} /></>}
  </span>;

  if (standing?.subscribed) {
    const deletes = standing.deletesAt?.toLocaleDateString("en-US", { month: "long", day: "numeric", timeZone: "UTC" });
    return <StatusScreen icon={<CreditCard />} title="Your share links are paused" footer={accountFooter}>
      Your hosting plan isn’t active, so viewers can’t open your links right now. Renew from Share in the
      BlitzRecorder app to bring them back.{" "}
      {deletes ? <>Renew before <span className="text-foreground">{deletes}</span> to keep your videos.</>
        : <>Videos are kept for {HOSTING_PLAN.retentionDaysAfterExpiry} days after a plan ends.</>}
    </StatusScreen>;
  }

  const videos = await ownerLibrary(account);
  const latest = videos.find((video) => video.status === "ready");
  if (latest) redirect(`/s/${latest.slug}`);

  if (videos.length > 0) {
    return <StatusScreen icon={<LoaderCircle className="animate-spin" />} title="Your video is almost ready"
      actions={<Button variant="outline" render={<Link href="/hosting/videos" />}><RotateCw /> Check again</Button>}
      footer={accountFooter}>
      We’re preparing your first shared video for streaming. This usually takes a minute or two.
    </StatusScreen>;
  }

  return <StatusScreen icon={<Film />} title="No shared videos yet" footer={accountFooter}>
    Open a recording in BlitzRecorder on your Mac, click <span className="text-foreground">Share video</span>, then
    <span className="text-foreground"> Create share link</span>. Your shared videos will show up here.
  </StatusScreen>;
}

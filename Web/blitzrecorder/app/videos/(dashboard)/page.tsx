import type { Metadata } from "next";
import Link from "next/link";
import { CreditCard, Film } from "lucide-react";
import { Button } from "@/components/ui/button";
import { LibraryFrame } from "@/components/hosting/library-frame";
import { StatusScreen } from "@/components/hosting/status-screen";
import { accountState, activeSessionCount } from "@/lib/hosting/account";
import { HOSTING_PLAN } from "@/lib/hosting/plan";
import { signInPath } from "@/lib/hosting/paths";
import { hostingStanding, ownerLibrary, viewerAccount } from "@/lib/hosting/web-session";
import { VideoLibrary } from "./library";

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
  if (!account) {
    return <LibraryFrame email={null}>
      <LibraryHeading />
      <div className="flex flex-col items-start gap-3 rounded-card bg-card px-5 py-8">
        <p className="max-w-md text-sm text-pretty text-muted-foreground">
          Sign in with the email you use in BlitzRecorder to see videos you have shared.
        </p>
        <Button render={<Link href={signInPath} />}>Sign in</Button>
      </div>
    </LibraryFrame>;
  }
  const [standing, sessions] = await Promise.all([
    accountState(account).active ? null : hostingStanding(account), activeSessionCount(account),
  ]);

  if (standing?.subscribed) {
    const deletes = standing.deletesAt?.toLocaleDateString("en-US", { month: "long", day: "numeric", timeZone: "UTC" });
    return <LibraryFrame email={account.email} sessions={sessions}>
      <div className="flex max-w-md flex-col gap-2 py-10">
        <CreditCard className="size-5 text-muted-foreground" />
        <h1 className="font-display text-2xl font-semibold tracking-tight text-balance">Your share links are paused</h1>
        <p className="text-sm text-pretty text-muted-foreground">
          Your hosting plan isn’t active, so viewers can’t open your links right now. Renew from Share in the
          BlitzRecorder app to bring them back.{" "}
          {deletes ? <>Renew before <span className="text-foreground">{deletes}</span> to keep your videos.</>
            : <>Videos are kept for {HOSTING_PLAN.retentionDaysAfterExpiry} days after a plan ends.</>}
        </p>
      </div>
    </LibraryFrame>;
  }

  const videos = await ownerLibrary(account);
  return <LibraryFrame email={account.email} sessions={sessions}>
    <LibraryHeading />
    {videos.length > 0 ? <VideoLibrary videos={videos} /> : <div className="flex flex-col items-start gap-2 rounded-card bg-card px-5 py-8">
      <Film className="size-5 text-faint" />
      <p className="text-sm text-muted-foreground">
        No hosted videos yet. In BlitzRecorder, open a recording and choose <span className="text-foreground">Share video</span>.
      </p>
    </div>}
  </LibraryFrame>;
};

const LibraryHeading = () => <div className="flex flex-col gap-1">
  <h1 className="font-display text-2xl font-semibold tracking-tight text-balance">Your videos</h1>
  <p className="max-w-xl text-sm text-pretty text-muted-foreground">
    Unlist turns the public link off and keeps the file. Stop sharing removes it.
  </p>
</div>;

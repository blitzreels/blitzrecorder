import type { Metadata } from "next";
import Link from "next/link";
import { Film } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/hosting/app-shell";
import { requireAppAccount } from "@/lib/hosting/app-page";
import { HOSTING_PLAN } from "@/lib/hosting/plan";
import { planPath, videosPath } from "@/lib/hosting/paths";
import { hostingStanding, ownerLibrary } from "@/lib/hosting/web-session";
import { VideoLibrary } from "../library";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Your videos — BlitzRecorder", robots: { index: false, follow: false } };

export default async function VideosPage() {
  const app = await requireAppAccount(videosPath);
  if (!app) return null;
  const [standing, videos] = await Promise.all([
    app.overview.subscribed ? null : hostingStanding(app.account), ownerLibrary(app.account),
  ]);
  const deletes = standing?.deletesAt?.toLocaleDateString("en-US", { month: "long", day: "numeric", timeZone: "UTC" });

  return <>
    <PageHeader title="Videos" description="Unlist turns a public link off and keeps the file. Stop sharing removes it." actions={null} />
    {standing?.subscribed ? <div className="product-surface mb-8 flex flex-col gap-3 rounded-[14px] px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
      <p className="text-[14px] leading-6 text-pretty text-muted-foreground">
        <span className="font-medium text-foreground">Your hosted links are paused.</span>{" "}
        {deletes ? <>Renew before {deletes} to keep these videos.</>
          : <>Videos are kept for {HOSTING_PLAN.retentionDaysAfterExpiry} days after a plan ends.</>}
      </p>
      <Button size="sm" render={<Link href={planPath} />}>Renew plan</Button>
    </div> : null}
    {videos.length > 0 ? <VideoLibrary videos={videos} /> : <EmptyLibrary />}
  </>;
}

const EmptyLibrary = () => <div className="product-surface flex flex-col items-center rounded-[20px] px-6 py-16 text-center">
  <span className="grid size-11 place-items-center rounded-tile bg-fill-control text-muted-foreground [&_svg]:size-5"><Film /></span>
  <p className="mt-5 text-[17px] font-semibold tracking-[-0.01em]">No shared videos yet</p>
  <p className="mt-2 max-w-sm text-[14px] leading-6 text-muted-foreground">
    In BlitzRecorder, open a recording and choose <span className="text-foreground">Share video</span>. It shows up here.
  </p>
</div>;

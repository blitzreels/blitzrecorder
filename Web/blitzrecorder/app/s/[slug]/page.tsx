import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { sharedAsset } from "@/lib/hosting/service";
import { required } from "@/lib/hosting/model";
import { ownerLibrary, viewerAccount } from "@/lib/hosting/web-session";
import { activeSessionCount } from "@/lib/hosting/account";
import { SharedVideoView, type SharedViewer } from "./shared-video-view";
import { EMPTY_DETAILS } from "@/lib/hosting/details";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Shared video", description: "Watch a video shared with BlitzRecorder.",
  robots: { index: false, follow: false, noarchive: true }, referrer: "no-referrer",
};

export default async function SharedVideoPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") notFound();
  const [asset, account] = await Promise.all([sharedAsset(slug), viewerAccount()]);
  if (!asset || !asset.width || !asset.height) notFound();
  const owner = account?.id === asset.account_id;
  const [library, sessions] = account && owner
    ? await Promise.all([ownerLibrary(account), activeSessionCount(account)]) : [null, 0];
  const viewer: SharedViewer | null = account && { email: account.email, library, sessions };
  const base = `${new URL(required("HOSTING_MEDIA_ORIGIN")).origin}/s/${slug}`;
  const has = (path: string) => asset.files.some((file) => file.path === path);
  return <SharedVideoView slug={asset.slug} source={`${base}/${has("video.mp4") ? "video.mp4" : "master.m3u8"}`}
    poster={has("poster.jpg") ? `${base}/poster.jpg` : ""}
    title={asset.title} width={asset.width} height={asset.height} duration={asset.duration ?? asset.declared_seconds}
    frameRate={asset.frame_rate} details={asset.viewer_details ?? EMPTY_DETAILS} viewer={viewer} />;
}

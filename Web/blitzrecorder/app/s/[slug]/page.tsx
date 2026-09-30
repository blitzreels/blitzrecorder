import type { Metadata } from "next";
import { cache } from "react";
import { notFound } from "next/navigation";
import { sharedAsset } from "@/lib/hosting/service";
import { required } from "@/lib/hosting/model";
import { ownerLibrary, viewerAccount } from "@/lib/hosting/web-session";
import { activeSessionCount } from "@/lib/hosting/account";
import { SharedVideoView, type SharedViewer } from "./shared-video-view";
import { shareDescription } from "@/lib/hosting/brief";
import { EMPTY_DETAILS, compactTranscript } from "@/lib/hosting/details";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Shared video", description: "Watch a video shared with BlitzRecorder.",
  robots: { index: false, follow: false, noarchive: true }, referrer: "no-referrer",
};

const loadShared = cache(async (slug: string) => {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return null;
  return sharedAsset(slug);
});

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const asset = await loadShared((await params).slug);
  if (!asset?.width || !asset.height) return {};
  const stored = asset.viewer_details ?? EMPTY_DETAILS;
  const details = { ...stored, transcript: compactTranscript(stored.transcript) };
  const duration = asset.duration ?? asset.declared_seconds;
  const description = shareDescription({ details, duration });
  const origin = process.env.HOSTING_MEDIA_ORIGIN;
  const poster = origin && asset.files.some((file) => file.path === "poster.jpg")
    ? `${new URL(origin).origin}/s/${asset.slug}/poster.jpg` : null;
  return {
    title: asset.title, description,
    openGraph: {
      title: asset.title, description, type: "website", url: `/s/${asset.slug}`,
      images: poster ? [{ url: poster, width: asset.width, height: asset.height, alt: asset.title }] : undefined,
    },
    twitter: {
      card: poster ? "summary_large_image" : "summary", title: asset.title, description,
      images: poster ? [poster] : undefined,
    },
  };
}

export default async function SharedVideoPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") notFound();
  const [asset, account] = await Promise.all([loadShared(slug), viewerAccount()]);
  if (!asset || !asset.width || !asset.height) notFound();
  const owner = account?.id === asset.account_id;
  const [library, sessions] = account && owner
    ? await Promise.all([ownerLibrary(account), activeSessionCount(account)]) : [null, 0];
  const viewer: SharedViewer | null = account && { email: account.email, library, sessions };
  const base = `${new URL(required("HOSTING_MEDIA_ORIGIN")).origin}/s/${slug}`;
  const has = (path: string) => asset.files.some((file) => file.path === path);
  const details = asset.viewer_details ?? EMPTY_DETAILS;
  return <SharedVideoView slug={asset.slug} source={`${base}/${has("video.mp4") ? "video.mp4" : "master.m3u8"}`}
    poster={has("poster.jpg") ? `${base}/poster.jpg` : ""}
    title={asset.title} width={asset.width} height={asset.height} duration={asset.duration ?? asset.declared_seconds}
    frameRate={asset.frame_rate} details={{ ...details, transcript: compactTranscript(details.transcript) }} viewer={viewer} />;
}

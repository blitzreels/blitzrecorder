import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { hasFile, loadShared, playablePath } from "./shared-asset";
import { mediaURL, previewSize } from "@/lib/hosting/model";
import { ownerLibrary, viewerAccount } from "@/lib/hosting/web-session";
import { SharedVideoView, type SharedViewer } from "./shared-video-view";
import { shareDescription } from "@/lib/hosting/brief";
import { EMPTY_DETAILS, shareDetails } from "@/lib/hosting/details";
import { embedPath, sharePath } from "@/lib/hosting/paths";
import { SITE_URL } from "@/lib/site";

export const dynamic = "force-dynamic";

const privatePage: Metadata = {
  robots: { index: false, follow: false, noarchive: true },
  referrer: "no-referrer",
};

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const asset = await loadShared((await params).slug);
  if (!asset?.width || !asset.height) {
    return { title: "Shared video", description: "Watch a video shared with BlitzRecorder.", ...privatePage };
  }
  const duration = asset.duration ?? asset.declared_seconds;
  const details = shareDetails({ details: asset.viewer_details ?? EMPTY_DETAILS, duration });
  const description = shareDescription({ details, duration });
  const hosted = Boolean(asset.media_origin || process.env.HOSTING_MEDIA_ORIGIN);
  const poster = hosted && hasFile({ asset, path: "poster.jpg" }) ? mediaURL({ asset, path: "poster.jpg" }) : null;
  const preview = hosted && hasFile({ asset, path: "preview.mp4" }) ? mediaURL({ asset, path: "preview.mp4" }) : null;
  const video = hosted && hasFile({ asset, path: "video.mp4" }) ? mediaURL({ asset, path: "video.mp4" }) : null;
  const stream = preview ?? video;
  return {
    title: asset.title, description, ...privatePage,
    openGraph: {
      title: asset.title, description, type: preview ? "video.other" : "website", url: sharePath(asset.slug),
      // Only the short preview: the full upload can be gigabytes, which Facebook, iMessage and Discord won't fetch.
      videos: preview ? [{ url: preview, secureUrl: preview.startsWith("https://") ? preview : undefined, type: "video/mp4",
        ...previewSize({ width: asset.width, height: asset.height }) }] : undefined,
      images: poster ? [{ url: poster, width: asset.width, height: asset.height, alt: asset.title }] : undefined,
    },
    twitter: stream && poster
      ? {
        card: "player", title: asset.title, description, images: [poster],
        players: [{ playerUrl: `${SITE_URL}${embedPath(asset.slug)}`, streamUrl: stream, width: asset.width, height: asset.height }],
      }
      : {
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
  const library = account && owner ? await ownerLibrary(account) : null;
  const viewer: SharedViewer | null = account && { email: account.email, library };
  const playable = playablePath(asset);
  if (!playable) notFound();
  const duration = asset.duration ?? asset.declared_seconds;
  const details = shareDetails({ details: asset.viewer_details ?? EMPTY_DETAILS, duration });
  return <SharedVideoView slug={asset.slug} source={mediaURL({ asset, path: playable })}
    poster={hasFile({ asset, path: "poster.jpg" }) ? mediaURL({ asset, path: "poster.jpg" }) : ""}
    title={asset.title} width={asset.width} height={asset.height} duration={duration}
    frameRate={asset.frame_rate} details={details} viewer={viewer} />;
}

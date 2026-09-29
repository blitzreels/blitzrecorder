import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { sharedAsset } from "@/lib/hosting/service";
import { required } from "@/lib/hosting/model";
import { SharedPlayer } from "./player";
import { EMPTY_DETAILS } from "@/lib/hosting/details";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Shared video", description: "Watch a video shared with BlitzRecorder.",
  robots: { index: false, follow: false, noarchive: true }, referrer: "no-referrer",
};

export default async function SharedVideoPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") notFound();
  const asset = await sharedAsset(slug);
  if (!asset || !asset.width || !asset.height) notFound();
  const base = `${new URL(required("HOSTING_MEDIA_ORIGIN")).origin}/s/${slug}`;
  return <main className="min-h-screen bg-background px-4 pb-12 text-foreground sm:px-8 lg:px-10">
    <header className="mx-auto flex max-w-[1440px] items-center justify-between py-7">
      <Link href="/" className="font-display text-lg font-bold tracking-tight">blitzrecorder<span className="text-emerald-400">.</span></Link>
      <span className="text-xs text-zinc-500">Video sharing</span>
    </header>
    <SharedPlayer key={asset.slug} source={`${base}/${asset.status === "ready" ? "master.m3u8" : "video.mp4"}`}
      poster={asset.files.some((file) => file.path === "poster.jpg") ? `${base}/poster.jpg` : null}
      title={asset.title} width={asset.width} height={asset.height} duration={asset.duration ?? asset.declared_seconds}
      frameRate={asset.frame_rate} details={asset.viewer_details ?? EMPTY_DETAILS} />
  </main>;
}

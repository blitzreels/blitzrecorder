import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { mediaURL } from "@/lib/hosting/model";
import { hasFile, loadShared, playablePath } from "../shared-asset";
import { EmbedPlayer } from "./embed-player";
import styles from "./embed.module.css";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const asset = await loadShared((await params).slug);
  return { title: asset?.title ?? "Shared video", robots: { index: false, follow: false, noarchive: true }, referrer: "no-referrer" };
}

/** The player X shows inside a post. Kept bare: no sharing UI, no notes, nothing that needs the full page. */
export default async function EmbeddedVideoPage({ params }: { params: Promise<{ slug: string }> }) {
  const asset = await loadShared((await params).slug);
  const playable = asset && playablePath(asset);
  if (!asset || !playable) notFound();
  return <main className={styles.frame}>
    <EmbedPlayer source={mediaURL({ asset, path: playable })} title={asset.title}
      poster={hasFile({ asset, path: "poster.jpg" }) ? mediaURL({ asset, path: "poster.jpg" }) : null} />
  </main>;
}

import { notFound } from "next/navigation";
import { LibraryFrame } from "@/components/hosting/library-frame";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import { VideoLibrary } from "../library";

const sample = "/videos/presentation.mp4";

const videos: Array<LibraryVideo & { clip: { src: string; start: number } }> = [
  { slug: "preview", title: "Product walkthrough", status: "ready", listed: true, duration: 30.3, createdAt: "2026-10-02T18:00:00.000Z", poster: "/media/presentation-poster.webp", clip: { src: sample, start: 1 } },
  { slug: "preview-unlisted-video1", title: "Investor call", status: "ready", listed: false, duration: 30.3, createdAt: "2026-10-02T16:00:00.000Z", poster: "/media/camera.webp", clip: { src: sample, start: 8 } },
  { slug: "preview-processing-vid01", title: "Studio tour", status: "processing", listed: true, duration: 30.3, createdAt: "2026-10-02T15:00:00.000Z", poster: "/media/screen.webp", clip: { src: sample, start: 16 } },
  { slug: "preview-failed-video-001", title: "Friday sync", status: "failed", listed: true, duration: 30.3, createdAt: "2026-10-02T12:00:00.000Z", poster: "/media/editor.webp", clip: { src: sample, start: 22 } },
];

/** Local fixture. Production 404s. Sign out only flips this page; it does not touch a real session. */
export default async function VideosPreview({ searchParams }: { searchParams: Promise<{ account?: string }> }) {
  if (process.env.NODE_ENV === "production") notFound();
  const signedOut = (await searchParams).account === "out";
  return <LibraryFrame email={signedOut ? null : "you@blitzrecorder.com"} videosHref="/videos/preview" signOutHref="/videos/preview?account=out">
    <div className="flex flex-col gap-1">
      <h1 className="font-display text-2xl font-semibold tracking-tight text-balance">Your videos</h1>
      <p className="max-w-xl text-sm text-pretty text-muted-foreground">
        Unlist turns the public link off and keeps the file. Stop sharing removes it.
      </p>
    </div>
    <VideoLibrary videos={videos} />
  </LibraryFrame>;
}

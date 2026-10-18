import { PageHeader } from "@/components/hosting/app-shell";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import { VideoLibrary } from "../library";

const sample = "/videos/presentation.mp4";

const videos: Array<LibraryVideo & { clip: { src: string; start: number } }> = [
  { slug: "preview", title: "Product walkthrough", status: "ready", listed: true, storage: "cloudflare", duration: 30.3, createdAt: "2026-10-02T18:00:00.000Z", poster: "/media/presentation-poster.webp", clip: { src: sample, start: 1 } },
  { slug: "preview-unlisted-video1", title: "Investor call", status: "ready", listed: false, storage: "blitzrecorder", duration: 30.3, createdAt: "2026-10-02T16:00:00.000Z", poster: "/media/take-camera.jpg", clip: { src: sample, start: 8 } },
  { slug: "preview-processing-vid01", title: "Studio tour", status: "processing", listed: true, storage: "blitzrecorder", duration: 30.3, createdAt: "2026-10-02T15:00:00.000Z", poster: "/media/take-screen.jpg", clip: { src: sample, start: 16 } },
  { slug: "preview-failed-video-001", title: "Friday sync", status: "failed", listed: true, storage: "blitzrecorder", duration: 30.3, createdAt: "2026-10-02T12:00:00.000Z", poster: "/media/editor.webp", clip: { src: sample, start: 22 } },
];

export default function VideosPreview() {
  return <>
    <PageHeader title="Videos" description="Unlist turns a public link off and keeps the file. Stop sharing removes it." actions={null} />
    <VideoLibrary videos={videos} />
  </>;
}

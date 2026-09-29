import Link from "next/link";
import { Link2Off } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SignOutButton } from "@/components/hosting/sign-out-button";
import { SiteMark } from "@/components/hosting/status-screen";
import type { VideoDetails } from "@/lib/hosting/details";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import { OwnerLibrary, OwnerLibraryProvider, OwnerLibraryToggle } from "./owner-library";
import styles from "./owner-library.module.css";
import { SharedPlayer } from "./player";
import { StopSharing } from "./stop-sharing";
import { TryBlitzRecorderCard } from "./try-blitzrecorder";
import { TRY_URL } from "./try-url";

/** `library` and `sessions` are only loaded when the viewer owns the video. */
export type SharedViewer = { email: string | null; library: LibraryVideo[] | null; sessions: number };

export function SharedVideoView({ slug, source, poster, title, width, height, duration, frameRate, details, viewer }: {
  slug: string; source: string; poster: string; title: string; width: number; height: number;
  duration: number; frameRate: number | null; details: VideoDetails; viewer: SharedViewer | null;
}) {
  const library = viewer?.library ?? null;
  const player = <SharedPlayer key={slug} source={source} poster={poster} title={title} width={width} height={height}
    duration={duration} frameRate={frameRate} details={details}
    ownerActions={library && <StopSharing slug={slug} title={title} current
      trigger={<Button variant="ghost" title="Stop sharing this video" />}><><Link2Off />Stop sharing</></StopSharing>}>
    {!viewer && <TryBlitzRecorderCard />}
  </SharedPlayer>;

  return <OwnerLibraryProvider>
    <main className="min-h-screen bg-background px-4 pb-16 text-foreground sm:px-6 lg:px-8">
      <header className={`mx-auto flex h-16 items-center justify-between gap-4 ${library ? "max-w-[1800px]" : "max-w-[1480px]"}`}>
        <div className="flex items-center gap-3">
          {library && <OwnerLibraryToggle count={library.length} />}
          <SiteMark />
        </div>
        {!viewer && <div className="flex items-center gap-1">
          <Button size="sm" variant="ghost" render={<Link href={`/hosting/sign-in?next=/s/${slug}`} prefetch={false} />}>
            Sign in
          </Button>
          <Button size="sm" render={<Link href={TRY_URL} />}>Try BlitzRecorder free</Button>
        </div>}
        {viewer && !library && <div className="flex items-center gap-1">
          <Button size="sm" variant="ghost" render={<Link href="/hosting/videos" />}>Your videos</Button>
          <SignOutButton />
        </div>}
      </header>
      {library
        ? <div className={styles.shell}>
          <OwnerLibrary videos={library} currentSlug={slug} email={viewer?.email ?? null} sessions={viewer?.sessions ?? 0} />
          {player}
        </div>
        : player}
    </main>
  </OwnerLibraryProvider>;
}

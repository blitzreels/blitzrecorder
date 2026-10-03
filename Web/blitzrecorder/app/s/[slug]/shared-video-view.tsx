import Link from "next/link";
import { Link2Off } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { ListingButton } from "@/components/hosting/listing-button";
import { SignOutButton } from "@/components/hosting/sign-out-button";
import { NavItem, SiteHeader } from "@/components/site/site-header";
import { cn } from "@/lib/utils";
import type { VideoDetails } from "@/lib/hosting/details";
import { sharePath, signInPath, videosPath } from "@/lib/hosting/paths";
import type { LibraryVideo } from "@/lib/hosting/web-session";
import { OwnerLibrary, OwnerLibraryProvider, OwnerLibraryToggle } from "./owner-library";
import styles from "./owner-library.module.css";
import { SharedPlayer } from "./player";
import { StopSharing } from "@/components/hosting/stop-sharing";
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
    ownerActions={library && <>
      <ListingButton slug={slug} listed title={title} redirectOnUnlist={videosPath}
        className="inline-flex h-[34px] items-center justify-center gap-2 rounded-control px-3 text-[13px] font-medium text-faint hover:bg-fill-quiet hover:text-foreground disabled:opacity-40" />
      <StopSharing slug={slug} title={title} current
        trigger={<Button variant="ghost" title="Stop sharing this video" />}><><Link2Off />Stop sharing</></StopSharing>
    </>}>
    {!viewer && <TryBlitzRecorderCard />}
  </SharedPlayer>;

  const bar = library ? "max-w-[1800px] px-4 sm:px-6 lg:px-8" : "max-w-[1480px] px-4 sm:px-6 lg:px-8";
  return <OwnerLibraryProvider>
    <main className="min-h-screen bg-background text-foreground">
      <SiteHeader
        compact={Boolean(library)}
        innerClassName={bar}
        leading={library ? <OwnerLibraryToggle count={library.length} /> : undefined}
        nav={<nav aria-label="Account"><NavItem href={videosPath}>Videos</NavItem></nav>}
        trailing={!viewer ? <>
          <Button size="sm" variant="ghost" render={<Link href={`${signInPath}?next=${sharePath(slug)}`} prefetch={false} />}>
            Sign in
          </Button>
          <Button size="sm" render={<Link href={TRY_URL} />}>
            <span className="sm:hidden">Try free</span>
            <span className="hidden sm:inline">Try BlitzRecorder free</span>
          </Button>
        </> : !library ? <SignOutButton className={cn(buttonVariants({ variant: "outline", size: "sm" }))} /> : <>
          <span className="hidden max-w-52 truncate text-[13px] text-faint md:inline" title={viewer.email ?? undefined}>{viewer.email}</span>
          <SignOutButton className={cn(buttonVariants({ variant: "outline", size: "sm" }))} />
        </>}
      />
      <div className="px-4 pb-16 sm:px-6 lg:px-8">
        {library
          ? <div className={styles.shell}>
            <OwnerLibrary videos={library} currentSlug={slug} email={viewer?.email ?? null} sessions={viewer?.sessions ?? 0} />
            {player}
          </div>
          : player}
      </div>
    </main>
  </OwnerLibraryProvider>;
}

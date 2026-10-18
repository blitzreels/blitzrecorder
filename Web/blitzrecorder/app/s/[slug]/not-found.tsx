import Link from "next/link";
import { Button } from "@/components/ui/button";
import { StatusScreen } from "@/components/hosting/status-screen";
import { signInPath, videosPath } from "@/lib/hosting/paths";
import { viewerAccount } from "@/lib/hosting/web-session";
import { TRY_URL } from "./try-url";

async function signedIn() {
  try { return Boolean(await viewerAccount()); } catch { return false; }
}

export default async function UnavailableVideo() {
  const owner = await signedIn();
  return <StatusScreen mark="404" title="This link isn’t working"
    actions={owner
      ? <Button size="lg" render={<Link href={videosPath} />}>Go to your videos</Button>
      : <>
        <Button size="lg" render={<Link href={TRY_URL} />}>Try BlitzRecorder free</Button>
        <Button size="lg" variant="outline" render={<Link href={signInPath} prefetch={false} />}>It’s my video, sign in</Button>
      </>}
    footer={owner ? "If you stopped sharing this video, share it again from the app to get a new link." : null}>
    The video may have been removed, sharing may have been turned off, or the link was copied incompletely.
    Ask the person who sent it for a new link.
  </StatusScreen>;
}

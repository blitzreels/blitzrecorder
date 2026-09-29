import Link from "next/link";
import { Link2Off } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusScreen } from "@/components/hosting/status-screen";
import { viewerAccount } from "@/lib/hosting/web-session";
import { TRY_URL } from "./try-url";

async function signedIn() {
  try { return Boolean(await viewerAccount()); } catch { return false; }
}

export default async function UnavailableVideo() {
  const owner = await signedIn();
  return <StatusScreen icon={<Link2Off />} title="This link isn’t working"
    actions={owner
      ? <Button render={<Link href="/hosting/videos" />}>Go to your videos</Button>
      : <>
        <Button variant="outline" render={<Link href="/hosting/sign-in" prefetch={false} />}>It’s my video, sign in</Button>
        <Button render={<Link href={TRY_URL} />}>Try BlitzRecorder free</Button>
      </>}
    footer={owner ? "If you stopped sharing this video, share it again from the app to get a new link." : null}>
    The video may have been removed, sharing may have been turned off, or the link was copied incompletely.
    Ask the person who sent it for a new link.
  </StatusScreen>;
}

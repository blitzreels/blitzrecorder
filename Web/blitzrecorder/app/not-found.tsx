import type { Metadata } from "next";
import Link from "next/link";
import { Problem } from "@/components/site/problem";
import { SiteNav } from "@/components/site/site-nav";
import { Button } from "@/components/ui/button";
import { videosPath } from "@/lib/hosting/paths";

export const metadata: Metadata = { title: "Page not found", robots: { index: false, follow: false } };

/** Every unmatched URL and every `notFound()` without a closer boundary. */
export default function NotFound() {
  return <main className="min-h-screen bg-background pt-14">
    <SiteNav />
    <Problem mark="404" title="This page isn’t here" fill footer={null} actions={<>
      <Button size="lg" render={<Link href="/" />}>Go home</Button>
      <Button size="lg" variant="outline" render={<Link href={videosPath} />}>Your videos</Button>
    </>}>
      The link may be old or mistyped. If someone sent you a video link, ask them for a fresh one.
    </Problem>
  </main>;
}

"use client";

import "./globals.css";
import Link from "next/link";
import { Problem } from "@/components/site/problem";
import { Button } from "@/components/ui/button";

/** Replaces the root layout when it fails, so it brings its own document, styles, and system font. */
export default function GlobalError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  return <html lang="en" className="dark" style={{ fontFamily: "system-ui, -apple-system, sans-serif" }}>
    <body>
      <title>Something went wrong · BlitzRecorder</title>
      <Problem mark="Error" title="BlitzRecorder couldn’t load" fill footer={error.digest ? `Reference ${error.digest}` : null}
        actions={<>
          <Button size="lg" onClick={retry}>Try again</Button>
          <Button size="lg" variant="outline" render={<Link href="/" />}>Go home</Button>
        </>}>
        Something failed while loading the site. Try again in a moment, or email support@blitzreels.com with the reference below.
      </Problem>
    </body>
  </html>;
}

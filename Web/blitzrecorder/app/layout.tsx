import type { Metadata } from "next";
import { Schibsted_Grotesk, Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import Script from "next/script";
import { readdir } from "node:fs/promises";
import path from "node:path";
import "./globals.css";
import { ReleaseProvider } from "@/components/site/release-context";
import {
  getLatestRelease,
  FALLBACK_VERSION,
  RELEASES_URL,
  type Release,
} from "@/lib/release";

/**
 * Self-hosted DMG fallback (server-only — uses fs, so it must not live in the
 * client-imported lib/release.ts). When the GitHub release lookup returns
 * nothing (rate limit, network blip, or no published DMG asset yet), serve the
 * newest DMG committed under public/downloads so the download CTA never 404s.
 */
async function resolveRelease(): Promise<Release | null> {
  const fromGitHub = await getLatestRelease();
  if (fromGitHub) return fromGitHub;
  try {
    const dir = path.join(process.cwd(), "public", "downloads");
    const dmgs = (await readdir(dir))
      .filter((name) => name.toLowerCase().endsWith(".dmg"))
      .sort();
    const dmg = dmgs.at(-1);
    if (!dmg) return null;
    return {
      version: FALLBACK_VERSION,
      tag: `v${FALLBACK_VERSION}`,
      dmgUrl: `/downloads/${dmg}`,
      htmlUrl: RELEASES_URL,
      publishedAt: null,
    };
  } catch {
    return null;
  }
}

const display = Schibsted_Grotesk({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["500", "700", "800", "900"],
});

const sans = Hanken_Grotesk({
  variable: "--font-sans",
  subsets: ["latin"],
});

const mono = JetBrains_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["500", "600"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://blitzrecorder.com"),
  title: {
    default: "BlitzRecorder: Mac screen recording for short-form",
    template: "%s · BlitzRecorder",
  },
  description:
    "Native macOS screen recorder for short-form video. Timeline, silence cuts, local files. Open source. Completely free.",
  openGraph: {
    title: "BlitzRecorder",
    siteName: "BlitzRecorder",
    description:
      "Mac screen recording for short-form. Open source. Completely free.",
    type: "website",
    url: "https://blitzrecorder.com",
  },
  twitter: {
    card: "summary_large_image",
  },
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const release = await resolveRelease();
  return (
    <html
      lang="en"
      className={`dark ${display.variable} ${sans.variable} ${mono.variable}`}
    >
      <body>
        <Script
          id="datafast-queue"
          strategy="afterInteractive"
          dangerouslySetInnerHTML={{
            __html: `
              window.datafast = window.datafast || function() {
                window.datafast.q = window.datafast.q || [];
                window.datafast.q.push(arguments);
              };
            `,
          }}
        />
        <Script
          defer
          data-website-id="dfid_BzjT2eJIF50AhugWpYPoM"
          data-domain="blitzrecorder.com"
          src="https://datafa.st/js/script.js"
          strategy="afterInteractive"
        />
        <ReleaseProvider release={release}>{children}</ReleaseProvider>
      </body>
    </html>
  );
}

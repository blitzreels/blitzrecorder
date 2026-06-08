import type { Metadata } from "next";
import { Schibsted_Grotesk, Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import Script from "next/script";
import "./globals.css";
import { ReleaseProvider } from "@/components/site/release-context";
import { getLatestRelease } from "@/lib/release";

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
    default: "BlitzRecorder: your iPhone is your studio camera",
    template: "%s · BlitzRecorder",
  },
  description:
    "BlitzRecorder turns your iPhone into a studio camera for your Mac. It records in full quality, so your videos look better than Continuity Camera.",
  openGraph: {
    title: "BlitzRecorder",
    siteName: "BlitzRecorder",
    description: "Your iPhone is your studio camera. It looks better than Continuity Camera.",
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
  const release = await getLatestRelease();
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

import type { Metadata } from "next";
import Link from "next/link";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { claimLicenseForCheckoutSession } from "@/lib/licenses";
import { LicenseCopy } from "./license-copy";

export const runtime = "nodejs";

// Private post-checkout page: keep it out of search results.
export const metadata: Metadata = {
  title: "Claim your license",
  description: "Reveal the BlitzRecorder license key from your checkout.",
  robots: { index: false, follow: false },
};

export default async function ClaimLicensePage({
  searchParams,
}: {
  searchParams: Promise<{ session_id?: string }>;
}) {
  const { session_id: sessionId } = await searchParams;
  let result:
    | { kind: "missing" }
    | { kind: "claimed"; licenseId: string; email: string; licenseKey: string }
    | { kind: "error"; message: string };

  if (!sessionId) {
    result = { kind: "missing" };
  } else {
    try {
      const license = await claimLicenseForCheckoutSession(sessionId);
      result = {
        kind: "claimed",
        licenseId: license.licenseId,
        email: license.email,
        licenseKey: license.licenseKey,
      };
    } catch (error) {
      result = {
        kind: "error",
        message: error instanceof Error ? error.message : "Unable to claim license",
      };
    }
  }

  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <SiteBackground />
      <SiteNav />
      <main>
        <Section width="sm" className="grid min-h-[80vh] place-items-center pt-32 pb-24 text-center">
          <Card className="glass ring-gradient w-full ring-0">
            <CardContent className="p-8 sm:p-10">
              {result.kind === "claimed" ? (
                <>
                  <Heading level={1}>License claimed.</Heading>
                  <Paragraph className="mt-4">
                    This lifetime Early Price license is assigned to{" "}
                    <span className="font-semibold text-foreground">{result.email}</span>.
                  </Paragraph>
                  <Paragraph tone="faint" size="sm" className="mt-3 font-mono">
                    {result.licenseId}
                  </Paragraph>
                  <LicenseCopy licenseId={result.licenseId} licenseKey={result.licenseKey} />
                  <Paragraph tone="faint" size="sm" className="mt-5">
                    Keep this key. The Mac app will use it to activate official builds.
                  </Paragraph>
                </>
              ) : result.kind === "missing" ? (
                <>
                  <Heading level={1}>Claim your license.</Heading>
                  <Paragraph className="mt-4">
                    Complete checkout first, then Stripe will send you back here to reveal your license key.
                  </Paragraph>
                  <Button render={<Link href="/#pricing" />} className="mt-7 h-11 rounded-full px-5">
                    View Early Price
                  </Button>
                </>
              ) : (
                <>
                  <Heading level={1}>License not ready.</Heading>
                  <Paragraph className="mt-4">{result.message}</Paragraph>
                  <Button render={<Link href="/#pricing" />} className="mt-7 h-11 rounded-full px-5">
                    Back to pricing
                  </Button>
                </>
              )}
            </CardContent>
          </Card>
        </Section>
      </main>
      <SiteFooter />
    </div>
  );
}

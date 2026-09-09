import type { Metadata } from "next";
import Link from "next/link";
import { JourneyPageView } from "@/components/site/journey-markers";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { TrackedLinkButton } from "@/components/site/tracked-link-button";
import { Card, CardContent } from "@/components/ui/card";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import {
  claimLicenseForCheckoutSession,
  emailFromFreeLicenseGrant,
  issueFreeLicense,
} from "@/lib/licenses";
import { LicenseCopy } from "./license-copy";

export const runtime = "nodejs";

export const metadata: Metadata = {
  title: "Claim your license",
  description: "Reveal the BlitzRecorder license key.",
  robots: { index: false, follow: false },
};

export default async function ClaimLicensePage({
  searchParams,
}: {
  searchParams: Promise<{ session_id?: string; grant?: string }>;
}) {
  const { session_id: sessionId, grant } = await searchParams;
  let result:
    | { kind: "missing" }
    | { kind: "claimed"; licenseId: string; email: string; licenseKey: string }
    | { kind: "error"; message: string };

  if (grant) {
    try {
      const email = emailFromFreeLicenseGrant(grant);
      const license = await issueFreeLicense(email);
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
  } else if (!sessionId) {
    result = { kind: "missing" };
  } else if (sessionId.startsWith("free_")) {
    result = {
      kind: "error",
      message: "Open the license page and enter your email again.",
    };
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
      <JourneyPageView
        area="license"
        eventName="license_claim_page_viewed"
        payload={{
          result: result.kind,
          has_session_id: Boolean(sessionId),
          has_grant: Boolean(grant),
        }}
      />
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
                    This license is assigned to{" "}
                    <span className="font-semibold text-foreground">{result.email}</span>.
                  </Paragraph>
                  <Paragraph tone="faint" size="sm" className="mt-3">
                    Keep this key for activation. The same email always returns the same key.
                  </Paragraph>
                  <Paragraph tone="faint" size="sm" className="mt-3 font-mono">
                    {result.licenseId}
                  </Paragraph>
                  <LicenseCopy licenseId={result.licenseId} licenseKey={result.licenseKey} />
                  <Paragraph tone="faint" size="sm" className="mt-5">
                    Open BlitzRecorder to activate automatically, or copy the key and paste it in Account.
                  </Paragraph>
                  <Paragraph tone="faint" size="sm" className="mt-2">
                    Don&apos;t have the app yet?{" "}
                    <Link href="/macos" className="font-medium text-primary underline-offset-4 hover:underline">
                      Download BlitzRecorder for Mac
                    </Link>
                    , then paste your key in Account.
                  </Paragraph>
                  <Paragraph tone="faint" size="sm" className="mt-4">
                    Recorder is free. When you want clips and captions,{" "}
                    <BlitzReelsLink
                      content="license_claim"
                      className="font-medium text-primary underline-offset-4 hover:underline"
                    >
                      open BlitzReels
                    </BlitzReelsLink>
                    .
                  </Paragraph>
                </>
              ) : result.kind === "missing" ? (
                <>
                  <Heading level={1}>Claim your license.</Heading>
                  <Paragraph className="mt-4">
                    Enter your email on the license page. We issue a key and bring you back here.
                  </Paragraph>
                  <TrackedLinkButton
                    href="/license"
                    label="Get a free license"
                    className="mt-7 h-11 rounded-full px-5"
                    area="license"
                    eventName="license_claim_cta_clicked"
                    payload={{ result: result.kind, cta: "get_free_license" }}
                  />
                </>
              ) : (
                <>
                  <Heading level={1}>License not ready.</Heading>
                  <Paragraph className="mt-4">{result.message}</Paragraph>
                  <TrackedLinkButton
                    href="/license"
                    label="Back to license"
                    className="mt-7 h-11 rounded-full px-5"
                    area="license"
                    eventName="license_claim_cta_clicked"
                    payload={{ result: result.kind, cta: "back_to_license" }}
                  />
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

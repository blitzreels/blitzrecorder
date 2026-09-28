"use client";

import { useEffect, useState } from "react";
import { ArrowUpRight, Copy, Check } from "@/components/site/icons";
import { Button } from "@/components/ui/button";
import { trackJourneyEvent } from "@/lib/journey-events";

export function LicenseCopy({
  licenseId,
  licenseKey,
}: {
  licenseId: string;
  licenseKey: string;
}) {
  const [copied, setCopied] = useState(false);
  const activationUrl = `blitzrecorder://activate?license_key=${encodeURIComponent(licenseKey)}`;

  useEffect(() => {
    trackJourneyEvent({
      eventName: "license_claimed",
      area: "license",
      payload: {
        plan: "free",
        license_id: licenseId,
      },
    });
  }, [licenseId]);

  async function copyLicense() {
    await navigator.clipboard.writeText(licenseKey);
    setCopied(true);
    trackJourneyEvent({
      eventName: "license_key_copied",
      area: "license",
      payload: {
        plan: "free",
        license_id: licenseId,
      },
    });
    window.setTimeout(() => setCopied(false), 1800);
  }

  function trackOpenApp() {
    trackJourneyEvent({
      eventName: "license_activation_deeplink_clicked",
      area: "license",
      payload: {
        plan: "free",
        license_id: licenseId,
      },
    });
  }

  return (
    <div className="mt-6">
      <pre className="max-h-48 overflow-auto rounded-control bg-fill-control p-4 text-left font-mono text-xs leading-relaxed text-muted-foreground">
        {licenseKey}
      </pre>
      <div className="mt-4 flex flex-col items-center justify-center gap-3 sm:flex-row">
        <Button
          render={<a href={activationUrl} onClick={trackOpenApp} />}
          size="lg"
        >
          <ArrowUpRight className="size-4" />
          Open BlitzRecorder to activate
        </Button>
        <Button onClick={copyLicense} variant="outline" size="lg">
          {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
          {copied ? "Copied" : "Copy key"}
        </Button>
      </div>
    </div>
  );
}

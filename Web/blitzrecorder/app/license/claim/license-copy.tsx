"use client";

import { useEffect, useState } from "react";
import { Copy, Check } from "@/components/site/icons";
import { Button } from "@/components/ui/button";

export function LicenseCopy({
  licenseId,
  licenseKey,
}: {
  licenseId: string;
  licenseKey: string;
}) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    try {
      window.datafast?.("license_claimed", {
        product: "blitzrecorder",
        plan: "early_lifetime",
        license_id: licenseId,
      });
    } catch {
      // Analytics should never block license display.
    }
  }, [licenseId]);

  async function copyLicense() {
    await navigator.clipboard.writeText(licenseKey);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="mt-6">
      <pre className="max-h-48 overflow-auto rounded-xl border border-border bg-background/70 p-4 text-left font-mono text-xs leading-relaxed text-muted-foreground">
        {licenseKey}
      </pre>
      <Button onClick={copyLicense} className="mt-4 h-11 rounded-full px-5">
        {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
        {copied ? "Copied" : "Copy license key"}
      </Button>
    </div>
  );
}

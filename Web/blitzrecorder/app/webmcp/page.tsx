import type { Metadata } from "next";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";

export const metadata: Metadata = {
  title: "Local WebMCP workspace",
  description: "Open the WebMCP workspace served by BlitzRecorder on your Mac.",
};

const facts = [
  { label: "Data", value: "Your local projects" },
  { label: "Transport", value: "127.0.0.1 only" },
  { label: "Upload", value: "None" },
];

export default function WebMCPPage() {
  return (
    <div className="relative min-h-screen overflow-x-clip">
      <SiteNav />
      <main>
        <Section width="md" className="flex min-h-[80vh] flex-col justify-center pt-32 pb-24">
          <p className="label-mono text-primary">Local WebMCP</p>
          <Heading level={1} className="mt-6 max-w-[14ch] text-[clamp(2.5rem,6vw,4.5rem)] leading-[0.95]">
            Your recordings stay inside BlitzRecorder.
          </Heading>
          <Paragraph className="mt-6 max-w-xl">
            The workspace is served by the Mac app on your loopback network.
            This public page does not load, copy, or simulate your recordings.
          </Paragraph>
          <div className="mt-9 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:gap-5">
            <Button size="lg" render={<a href="http://127.0.0.1:18473/webmcp" />}>
              Open local workspace
            </Button>
            <span className="text-sm text-faint">Requires BlitzRecorder to be open on this Mac</span>
          </div>
          <dl className="panel mt-14 grid rounded-card sm:grid-cols-3">
            {facts.map((fact) => (
              <div key={fact.label} className="border-t border-separator p-5 first:border-t-0 sm:border-t-0 sm:border-l sm:first:border-l-0 sm:p-6">
                <dt className="label-mono text-faint">{fact.label}</dt>
                <dd className="mt-3 font-display text-lg font-bold tracking-[-0.01em]">{fact.value}</dd>
              </div>
            ))}
          </dl>
        </Section>
      </main>
      <SiteFooter />
    </div>
  );
}

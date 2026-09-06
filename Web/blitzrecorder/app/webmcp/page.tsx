import type { Metadata } from "next";
import { SiteBackground } from "@/components/site/site-background";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteNav } from "@/components/site/site-nav";

export const metadata: Metadata = {
  title: "Local WebMCP workspace",
  description: "Open the WebMCP workspace served by BlitzRecorder on your Mac.",
};

export default function WebMCPPage() {
  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      <SiteBackground />
      <SiteNav />
      <main className="mx-auto flex min-h-[calc(100vh-1px)] w-[min(880px,calc(100%-32px))] items-center py-32">
        <section className="w-full">
          <p className="font-mono text-xs font-semibold uppercase tracking-[0.18em] text-primary">
            Local WebMCP
          </p>
          <h1 className="mt-5 max-w-3xl font-display text-5xl font-black tracking-[-0.045em] text-foreground sm:text-7xl">
            Your recordings stay inside BlitzRecorder.
          </h1>
          <p className="mt-7 max-w-2xl text-lg leading-8 text-muted-foreground">
            The workspace is served by the macOS app on your loopback network.
            This public page does not load, copy, or simulate your recordings.
          </p>

          <div className="mt-10 flex flex-col items-start gap-4 sm:flex-row sm:items-center">
            <a
              href="http://127.0.0.1:18473/webmcp"
              className="inline-flex h-12 items-center justify-center rounded-full bg-primary px-6 text-sm font-bold text-primary-foreground transition-colors hover:bg-primary/80"
            >
              Open local workspace
            </a>
            <span className="font-mono text-xs text-faint">
              Requires BlitzRecorder to be open on this Mac
            </span>
          </div>

          <div className="mt-16 grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-3">
            <Fact label="Data" value="Real local projects" />
            <Fact label="Transport" value="127.0.0.1 only" />
            <Fact label="Upload" value="None" />
          </div>
        </section>
      </main>
      <SiteFooter />
    </div>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-card/80 p-6 backdrop-blur-sm">
      <p className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-faint">
        {label}
      </p>
      <p className="mt-3 font-display text-lg font-bold text-foreground">{value}</p>
    </div>
  );
}

import Link from "next/link";
import Image from "next/image";
import { ArrowUpRight } from "@/components/site/icons";
import { Container } from "@/components/ui/layout";
import { Paragraph } from "@/components/ui/typography";
import { VersionTag } from "@/components/site/download-button";
import { assets } from "@/lib/assets";
import { ALGOMAX_URL } from "@/lib/content";
import { GITHUB_REPO_URL } from "@/lib/release";

type FooterLink = { label: string; href: string; external?: boolean };

const productLinks: FooterLink[] = [
  { label: "macOS app", href: "/macos" },
  { label: "iOS camera app", href: "/ios" },
  { label: "Pricing", href: "/#pricing" },
];

const resourceLinks: FooterLink[] = [
  { label: "Claim license", href: "/license" },
  { label: "Support", href: "/support" },
  { label: "Privacy", href: "/privacy" },
  { label: "Terms", href: "/terms" },
];

export function SiteFooter() {
  return (
    <footer className="relative border-t border-border bg-card/30">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-px"
        style={{
          background:
            "linear-gradient(to right, transparent, rgba(94,242,175,0.45), transparent)",
        }}
      />
      <Container>
        <div className="grid gap-12 py-16 sm:grid-cols-2 lg:grid-cols-[1.6fr_1fr_1fr] lg:gap-16">
          <div className="max-w-sm">
            <Link href="/" className="inline-flex items-center gap-2.5">
              <Image src={assets.macIcon} width={36} height={36} alt="" className="rounded-[22%]" />
              <span className="font-display text-lg font-bold tracking-tight">BlitzRecorder</span>
            </Link>
            <Paragraph tone="faint" size="sm" className="mt-4">
              Turn your iPhone into a camera for your Mac. Record locally on the phone and edit later
              without filming again.
            </Paragraph>

            <div className="mt-7 flex flex-col gap-3">
              <a
                href={ALGOMAX_URL}
                target="_blank"
                rel="noopener"
                className="group inline-flex items-center gap-1.5 text-sm text-faint transition-colors hover:text-foreground"
              >
                Built by Algomax
                <ArrowUpRight className="size-3.5 opacity-0 transition-opacity group-hover:opacity-100" />
              </a>
            </div>
          </div>

          <FooterNav title="Product" links={productLinks} />
          <FooterNav title="Resources" links={resourceLinks} />
        </div>

        <div className="flex flex-col items-start justify-between gap-4 border-t border-border py-7 text-sm text-faint sm:flex-row sm:items-center">
          <Paragraph tone="faint" size="sm">
            &copy; 2026{" "}
            <a
              href={ALGOMAX_URL}
              target="_blank"
              rel="noopener"
              className="font-medium text-muted-foreground transition-colors hover:text-foreground"
            >
              Algomax
            </a>
            . Made in Strasbourg, France.
          </Paragraph>
          <div className="flex items-center gap-6">
            <VersionTag className="font-mono text-xs text-muted-foreground transition-colors hover:text-foreground" />
            <a
              href={GITHUB_REPO_URL}
              target="_blank"
              rel="noopener"
              className="transition-colors hover:text-foreground"
            >
              GitHub repo
            </a>
            <a
              href={ALGOMAX_URL}
              target="_blank"
              rel="noopener"
              className="transition-colors hover:text-foreground"
            >
              Algomax
            </a>
          </div>
        </div>
      </Container>
    </footer>
  );
}

function FooterNav({ title, links }: { title: string; links: FooterLink[] }) {
  return (
    <nav className="text-sm" aria-label={title}>
      <p className="font-display font-bold">{title}</p>
      <ul className="mt-4 flex flex-col gap-3 text-muted-foreground">
        {links.map((link) => (
          <li key={link.href}>
            {link.external ? (
              <a
                className="transition-colors hover:text-foreground"
                href={link.href}
                target="_blank"
                rel="noopener"
              >
                {link.label}
              </a>
            ) : (
              <Link className="transition-colors hover:text-foreground" href={link.href}>
                {link.label}
              </Link>
            )}
          </li>
        ))}
      </ul>
    </nav>
  );
}

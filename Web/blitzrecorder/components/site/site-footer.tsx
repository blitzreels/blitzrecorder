import Link from "next/link";
import Image from "next/image";
import { Container } from "@/components/ui/layout";
import { VersionTag } from "@/components/site/download-button";
import { assets } from "@/lib/assets";
import { ALGOMAX_URL } from "@/lib/content";
import { BlitzReelsLink } from "@/components/site/blitzreels-link";
import { GITHUB_REPO_URL, RELEASES_URL } from "@/lib/release";

type FooterLink =
  | { kind: "internal"; label: string; href: string }
  | { kind: "external"; label: string; href: string }
  | { kind: "blitzreels"; label: string; content: string };

const productLinks: FooterLink[] = [
  { kind: "internal", label: "Mac app", href: "/macos" },
  { kind: "internal", label: "iPhone camera", href: "/ios" },
  { kind: "external", label: "Windows Studio", href: RELEASES_URL },
  { kind: "external", label: "Release notes", href: RELEASES_URL },
];

const resourceLinks: FooterLink[] = [
  { kind: "internal", label: "Support", href: "/support" },
  { kind: "internal", label: "Privacy", href: "/privacy" },
  { kind: "internal", label: "Terms", href: "/terms" },
  { kind: "internal", label: "Legacy licenses", href: "/license" },
];

const sourceLinks: FooterLink[] = [
  { kind: "external", label: "GitHub", href: GITHUB_REPO_URL },
  { kind: "external", label: "AGPL-3.0 license", href: `${GITHUB_REPO_URL}/blob/main/LICENSE` },
  { kind: "blitzreels", label: "BlitzReels", content: "footer_nav" },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-separator">
      <Container>
        <div className="grid gap-12 py-16 sm:grid-cols-3 lg:grid-cols-[1.5fr_1fr_1fr_1fr]">
          <div className="max-w-xs sm:col-span-3 lg:col-span-1">
            <Link href="/" className="inline-flex items-center gap-2.5">
              <Image src={assets.macIcon} width={32} height={32} alt="" className="rounded-[22%]" />
              <span className="font-display text-lg font-bold tracking-[-0.02em]">BlitzRecorder</span>
            </Link>
            <p className="mt-4 text-sm leading-6 text-faint">
              Record and edit on your Mac. Free and open source.
            </p>
            <BlitzReelsLink
              content="footer_byline"
              className="mt-7 inline-flex items-center gap-2.5 text-sm text-faint transition-colors hover:text-foreground"
            >
              A project by
              <Image src={assets.blitzreelsWordmark} alt="BlitzReels" width={107} height={16} className="h-4 w-auto opacity-80" />
            </BlitzReelsLink>
          </div>
          <FooterNav title="Product" links={productLinks} />
          <FooterNav title="Help" links={resourceLinks} />
          <FooterNav title="Source" links={sourceLinks} />
        </div>

        <div className="flex flex-col items-start justify-between gap-3 border-t border-separator py-7 text-sm text-faint sm:flex-row sm:items-center">
          <p>
            &copy; 2026{" "}
            <a href={ALGOMAX_URL} target="_blank" rel="noopener" className="transition-colors hover:text-foreground">
              Algomax
            </a>
            . Made in Strasbourg, France.
          </p>
          <VersionTag className="font-mono text-xs" />
        </div>
      </Container>
    </footer>
  );
}

function FooterNav({ title, links }: { title: string; links: FooterLink[] }) {
  return (
    <nav className="text-sm" aria-label={title}>
      <p className="label-mono text-faint">{title}</p>
      <ul className="mt-4 flex flex-col gap-3 text-muted-foreground">
        {links.map((link) => (
          <li key={link.label}>
            <FooterAnchor link={link} />
          </li>
        ))}
      </ul>
    </nav>
  );
}

function FooterAnchor({ link }: { link: FooterLink }) {
  const className = "transition-colors hover:text-foreground";
  switch (link.kind) {
    case "blitzreels":
      return (
        <BlitzReelsLink content={link.content} className={className}>
          {link.label}
        </BlitzReelsLink>
      );
    case "external":
      return (
        <a className={className} href={link.href} target="_blank" rel="noopener">
          {link.label}
        </a>
      );
    case "internal":
      return (
        <Link className={className} href={link.href}>
          {link.label}
        </Link>
      );
  }
}

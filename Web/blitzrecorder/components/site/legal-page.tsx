"use client";

import { SiteNav } from "@/components/site/site-nav";
import { SiteFooter } from "@/components/site/site-footer";
import { Container, Article } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { legalPages } from "@/lib/content";

export function LegalPage({ slug }: { slug: "terms" | "privacy" | "support" }) {
  const page = legalPages[slug];
  return (
    <div className="min-h-screen">
      <SiteNav />
      <main>
        <Container width="sm" className="pt-36 pb-28">
          <Heading level={1} className="text-[clamp(2.5rem,5vw,3.75rem)]">
            {page.title}
          </Heading>
          <p className="mt-4 text-sm text-faint">{page.eyebrow}</p>
          <Paragraph className="mt-8 max-w-2xl">{page.intro}</Paragraph>
          <div className="mt-12 flex flex-col">
            {page.sections.map((section) => (
              <Article className="grid gap-2 py-7 md:grid-cols-[14rem_1fr] md:gap-10" key={section.title}>
                <Heading as="h2" level={4}>
                  {section.title}
                </Heading>
                <Paragraph size="base">{section.body}</Paragraph>
              </Article>
            ))}
          </div>
        </Container>
      </main>
      <SiteFooter />
    </div>
  );
}

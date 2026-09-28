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
        <Container width="sm" className="pt-32 pb-20">
          <p className="label-mono text-faint">{page.eyebrow}</p>
          <Heading level={1} className="mt-5 text-[clamp(2.5rem,6vw,4rem)] leading-[0.95]">
            {page.title}
          </Heading>
          <Paragraph className="mt-6 max-w-2xl">{page.intro}</Paragraph>
          <div className="mt-12 flex flex-col">
            {page.sections.map((section) => (
              <Article className="grid gap-3 border-t border-separator py-8 md:grid-cols-[14rem_1fr] md:gap-10" key={section.title}>
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

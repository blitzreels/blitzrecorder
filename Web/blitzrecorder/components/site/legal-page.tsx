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
          <Paragraph tone="faint" size="sm" className="font-medium">
            {page.eyebrow}
          </Paragraph>
          <Heading level={1} className="mt-3 leading-[0.98]">
            {page.title}
          </Heading>
          <Paragraph className="mt-6 max-w-2xl text-xl">{page.intro}</Paragraph>
          <div className="mt-12 flex flex-col gap-8 border-t border-border pt-10">
            {page.sections.map((section) => (
              <Article className="flex flex-col gap-3 border-b border-border pb-8" key={section.title}>
                <Heading as="h2" level={3} className="text-2xl">
                  {section.title}
                </Heading>
                <Paragraph>{section.body}</Paragraph>
              </Article>
            ))}
          </div>
        </Container>
      </main>
      <SiteFooter />
    </div>
  );
}

import type { Metadata } from "next";
import { LegalPage } from "@/components/site/legal-page";
import { legalPages } from "@/lib/content";

export const metadata: Metadata = {
  title: legalPages.support.title,
  description: legalPages.support.intro,
};

export default function Page() {
  return <LegalPage slug="support" />;
}

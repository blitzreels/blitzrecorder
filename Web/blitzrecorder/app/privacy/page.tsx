import type { Metadata } from "next";
import { LegalPage } from "@/components/site/legal-page";
import { legalPages } from "@/lib/content";

export const metadata: Metadata = {
  title: legalPages.privacy.title,
  description: legalPages.privacy.intro,
};

export default function Page() {
  return <LegalPage slug="privacy" />;
}

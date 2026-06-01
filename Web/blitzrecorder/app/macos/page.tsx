import type { Metadata } from "next";
import { ProductPage } from "@/components/site/product-page";
import { pages } from "@/lib/content";

export const metadata: Metadata = {
  title: "BlitzRecorder: Mac recording studio",
  description: pages.macos.hero,
};

export default function Page() {
  return <ProductPage variant="macos" />;
}

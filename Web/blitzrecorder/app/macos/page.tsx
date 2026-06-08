import type { Metadata } from "next";
import { ProductPage } from "@/components/site/product-page";
import { pages } from "@/lib/content";

// The layout template appends "· BlitzRecorder", so no brand here.
export const metadata: Metadata = {
  title: "Mac recording studio",
  description: pages.macos.hero,
};

export default function Page() {
  return <ProductPage variant="macos" />;
}

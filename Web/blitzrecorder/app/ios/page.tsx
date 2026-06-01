import type { Metadata } from "next";
import { ProductPage } from "@/components/site/product-page";
import { pages } from "@/lib/content";

export const metadata: Metadata = {
  title: "BlitzRecorder Camera: iPhone camera for Mac",
  description: pages.ios.hero,
};

export default function Page() {
  return <ProductPage variant="ios" />;
}

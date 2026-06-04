import type { Metadata } from "next";
import { ProductPage } from "@/components/site/product-page";
import { pages } from "@/lib/content";

// The layout template appends "· BlitzRecorder", so no brand here.
export const metadata: Metadata = {
  title: "Camera: your iPhone as a Mac camera",
  description: pages.ios.hero,
};

export default function Page() {
  return <ProductPage variant="ios" />;
}

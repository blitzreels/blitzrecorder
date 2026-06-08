import type { MetadataRoute } from "next";

const SITE = "https://blitzrecorder.com";

export default function sitemap(): MetadataRoute.Sitemap {
  const routes = ["", "/macos", "/ios", "/support", "/privacy", "/terms", "/license"];
  return routes.map((path) => ({
    url: `${SITE}${path}`,
    changeFrequency: "weekly",
    priority: path === "" ? 1 : 0.7,
  }));
}

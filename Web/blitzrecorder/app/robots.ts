import type { MetadataRoute } from "next";

const SITE = "https://blitzrecorder.com";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // Private post-checkout page and machine endpoints stay out of the index.
        disallow: ["/license/claim", "/api/"],
      },
    ],
    sitemap: `${SITE}/sitemap.xml`,
    host: SITE,
  };
}

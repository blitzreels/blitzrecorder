import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Tailwind keeps the stylesheet small; inlining it removes the render-blocking request for first visits.
  experimental: { inlineCss: true },
  async headers() {
    return [
      // No other site may frame our pages (clickjacking on owner controls), except the player X shows in posts.
      { source: "/:path*", headers: [{ key: "Content-Security-Policy", value: "frame-ancestors 'none'" }] },
      { source: "/s/:slug/embed", headers: [{ key: "Content-Security-Policy", value: "frame-ancestors https:" }] },
    ];
  },
  async redirects() {
    return [
      // Legacy static .html paths → clean routes
      { source: "/brand-guidelines.html", destination: "/brand-guidelines", permanent: true },
      { source: "/ios-app-store.html", destination: "/ios", permanent: true },
      { source: "/macos-app-store.html", destination: "/macos", permanent: true },
      { source: "/privacy.html", destination: "/privacy", permanent: true },
      { source: "/support.html", destination: "/support", permanent: true },
      { source: "/terms.html", destination: "/terms", permanent: true },
      // People type /pricing; the price lives on home.
      { source: "/pricing", destination: "/#free", permanent: false },
      { source: "/hosting/videos", destination: "/videos", permanent: false },
      { source: "/hosting/sign-in", destination: "/sign-in", permanent: false },
      { source: "/hosting/complete", destination: "/billing", permanent: false },
      // www → apex
      {
        source: "/:path*",
        has: [{ type: "host", value: "www.blitzrecorder.com" }],
        destination: "https://blitzrecorder.com/:path*",
        permanent: true,
      },
    ];
  },
};

export default nextConfig;

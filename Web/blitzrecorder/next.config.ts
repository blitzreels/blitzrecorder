import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async redirects() {
    return [
      // Legacy static .html paths → clean routes
      { source: "/brand-guidelines.html", destination: "/brand-guidelines", permanent: true },
      { source: "/ios-app-store.html", destination: "/ios", permanent: true },
      { source: "/macos-app-store.html", destination: "/macos", permanent: true },
      { source: "/privacy.html", destination: "/privacy", permanent: true },
      { source: "/support.html", destination: "/support", permanent: true },
      { source: "/terms.html", destination: "/terms", permanent: true },
      // People type /pricing and external links assume it; pricing lives on home.
      { source: "/pricing", destination: "/#pricing", permanent: false },
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

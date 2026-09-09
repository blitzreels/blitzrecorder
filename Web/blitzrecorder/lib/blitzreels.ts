export const BLITZREELS_ORIGIN = "https://www.blitzreels.com";

export function blitzreelsUrl(content: string): string {
  const url = new URL(BLITZREELS_ORIGIN);
  url.searchParams.set("utm_source", "blitzrecorder");
  url.searchParams.set("utm_medium", "website");
  url.searchParams.set("utm_campaign", "blitzrecorder-free");
  url.searchParams.set("utm_content", content);
  return url.toString();
}

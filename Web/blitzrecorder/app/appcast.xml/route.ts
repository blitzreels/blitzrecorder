import { RELEASES_URL } from "@/lib/release";

export function GET() {
  return new Response(null, {
    status: 307,
    headers: {
      Location: `${RELEASES_URL}/latest/download/appcast.xml`,
      "Cache-Control": "public, max-age=300",
    },
  });
}

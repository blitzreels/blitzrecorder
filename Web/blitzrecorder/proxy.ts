import { trackAICrawlerRequest } from "@datafast/ai-crawl";
import {
  NextResponse,
  type NextFetchEvent,
  type NextRequest,
} from "next/server";

const DATAFAST_WEBSITE_ID = "dfid_BzjT2eJIF50AhugWpYPoM";

export function proxy(request: NextRequest, event: NextFetchEvent) {
  trackAICrawlerRequest(request, event, {
    websiteId: DATAFAST_WEBSITE_ID,
    domain: "blitzrecorder.com",
  });

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};

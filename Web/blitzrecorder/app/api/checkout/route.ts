import { type NextRequest } from "next/server";
import { handleFreeLicenseIssue } from "@/lib/license-issue";

export const runtime = "nodejs";

/** Kept as an alias so older forms still land on the free license claim. */
export async function POST(request: NextRequest) {
  return handleFreeLicenseIssue(request);
}

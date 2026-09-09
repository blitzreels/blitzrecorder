import { type NextRequest } from "next/server";
import { handleFreeLicenseIssue } from "@/lib/license-issue";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  return handleFreeLicenseIssue(request);
}

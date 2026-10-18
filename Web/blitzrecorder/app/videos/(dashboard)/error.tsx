"use client";

import { ErrorScreen } from "@/components/hosting/error-screen";

/** Errors in a dashboard page render inside the shell; the sidebar keeps working. */
export default function DashboardError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  return <ErrorScreen error={error} retry={retry} subject="this page" chrome="inline" />;
}

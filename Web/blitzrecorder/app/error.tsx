"use client";

import { ErrorScreen } from "@/components/hosting/error-screen";

export default function RootError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  return <ErrorScreen error={error} retry={retry} subject="this page" chrome="page" />;
}

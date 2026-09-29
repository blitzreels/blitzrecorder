"use client";

import { ErrorScreen } from "@/components/hosting/error-screen";

export default function SharedVideoError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <ErrorScreen error={error} reset={reset} subject="this video" />;
}

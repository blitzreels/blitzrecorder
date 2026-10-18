"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Problem } from "@/components/site/problem";
import { StatusScreen } from "./status-screen";

/**
 * Body of every `error.tsx`. `retry` is Next's refetch-and-rerender; `page` draws its own bar,
 * `inline` sits inside a layout that already has one (the dashboard shell).
 */
export const ErrorScreen = ({ error, retry, subject, chrome }: {
  error: Error & { digest?: string }; retry: () => void; subject: string; chrome: "page" | "inline";
}) => {
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    const update = () => setOffline(!navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => { window.removeEventListener("online", update); window.removeEventListener("offline", update); };
  }, []);

  useEffect(() => { console.error(error); }, [error]);

  const props = {
    mark: offline ? "Offline" : "Error",
    title: offline ? "You’re offline" : `We couldn’t load ${subject}`,
    actions: <>
      <Button size="lg" onClick={retry}>Try again</Button>
      <Button size="lg" variant="outline" render={<Link href="/" />}>Go home</Button>
    </>,
    footer: error.digest ? <>Reference <span className="font-mono">{error.digest}</span></> : null,
    children: offline
      ? "Reconnect to the internet, then try again."
      : "Something failed on our side. It usually clears up in a moment. If it keeps happening, email support@blitzreels.com with the reference below.",
  };
  return chrome === "page" ? <StatusScreen {...props} /> : <Problem {...props} fill={false} />;
};

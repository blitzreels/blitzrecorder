"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { RotateCw, WifiOff, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusScreen } from "./status-screen";

export const ErrorScreen = ({ error, reset, subject }: {
  error: Error & { digest?: string }; reset: () => void; subject: string;
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

  return <StatusScreen icon={offline ? <WifiOff /> : <TriangleAlert />}
    title={offline ? "You’re offline" : `We couldn’t load ${subject}`}
    actions={<>
      <Button onClick={reset}><RotateCw /> Try again</Button>
      <Button variant="ghost" render={<Link href="/" />}>Go to BlitzRecorder</Button>
    </>}
    footer={error.digest ? <>Error reference <span className="font-mono">{error.digest}</span></> : null}>
    {offline
      ? "Reconnect to the internet, then try again."
      : "This is on our side, not yours. It usually clears up in a moment. If it keeps happening, email support@blitzreels.com with the reference below."}
  </StatusScreen>;
};

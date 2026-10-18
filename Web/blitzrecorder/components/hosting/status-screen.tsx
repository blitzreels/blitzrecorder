import type { ReactNode } from "react";
import { Problem } from "@/components/site/problem";
import { SiteHeader } from "@/components/site/site-header";

const appBar = "max-w-[1480px] px-4 sm:px-6";

/** Full-page status for the video area: the app bar on top, `Problem` centered below. */
export const StatusScreen = ({ mark, title, children, actions, footer }: {
  mark: string; title: string; children: ReactNode; actions: ReactNode; footer: ReactNode | null;
}) => <main className="flex min-h-screen flex-col bg-background text-foreground">
  <SiteHeader innerClassName={appBar} />
  <Problem mark={mark} title={title} actions={actions} footer={footer} fill>{children}</Problem>
</main>;

import { SiteNav } from "@/components/site/site-nav";
import { SiteFooter } from "@/components/site/site-footer";
import { LoopingVideos } from "@/components/site/looping-videos";

export function ProductShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <SiteNav />
      <LoopingVideos />
      {children}
      <SiteFooter />
    </div>
  );
}

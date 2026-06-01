import { SiteNav } from "@/components/site/site-nav";
import { SiteFooter } from "@/components/site/site-footer";
import { SiteBackground } from "@/components/site/site-background";

export function ProductShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <SiteBackground />
      <SiteNav />
      {children}
      <SiteFooter />
    </div>
  );
}

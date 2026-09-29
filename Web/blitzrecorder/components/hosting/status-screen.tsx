import Link from "next/link";
import type { ReactNode } from "react";

export const SiteMark = () => <Link href="/" className="font-display text-[17px] font-bold tracking-tight">
  blitzrecorder<span className="text-primary">.</span>
</Link>;

export const StatusScreen = ({ icon, title, children, actions, footer }: {
  icon: ReactNode; title: string; children: ReactNode; actions?: ReactNode; footer?: ReactNode;
}) => <main className="flex min-h-screen flex-col bg-background px-4 text-foreground sm:px-6">
  <header className="mx-auto flex h-16 w-full max-w-[1480px] items-center"><SiteMark /></header>
  <section className="mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-center gap-6 pb-[12vh] text-center">
    <span className="flex size-12 items-center justify-center rounded-tile bg-fill-control text-muted-foreground [&_svg]:size-5">
      {icon}
    </span>
    <div className="flex flex-col gap-2">
      <h1 className="font-display text-2xl font-semibold tracking-tight text-balance">{title}</h1>
      <div className="text-sm leading-relaxed text-pretty text-muted-foreground">{children}</div>
    </div>
    {actions && <div className="flex flex-wrap items-center justify-center gap-2">{actions}</div>}
    {footer && <div className="text-xs text-faint">{footer}</div>}
  </section>
</main>;

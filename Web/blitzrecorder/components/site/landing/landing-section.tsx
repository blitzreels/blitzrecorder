import type { ReactNode } from "react";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";

/**
 * Every landing section has the same frame: one 1120px column, the same vertical rhythm,
 * a centered title and outcome line, an optional action, then the proof below it.
 */
export function LandingSection({ id, section, title, intro, action, children }: {
  id: string;
  section: string;
  title: ReactNode;
  intro: ReactNode;
  action: ReactNode | null;
  children: ReactNode;
}) {
  return (
    <Section id={id} width="page" className="scroll-mt-24 py-16 sm:py-24">
      <JourneySectionView area="landing" section={section} payload={{ page: "home" }} />
      <div className="mx-auto flex max-w-[46rem] flex-col items-center text-center">
        <h2 className="type-title text-[clamp(2.25rem,4.4vw,3.75rem)]">{title}</h2>
        <p className="mt-5 max-w-[44ch] text-lg leading-8 text-pretty text-muted-foreground">{intro}</p>
        {action ? <div className="mt-9 flex w-full justify-center">{action}</div> : null}
      </div>
      <div className="mt-12 sm:mt-16">{children}</div>
    </Section>
  );
}

import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading } from "@/components/ui/typography";

const items = [
  {
    label: "Projects",
    title: "Every take in one library",
    body: "Preview the latest export, rename takes, copy transcripts, and open the files in Finder.",
  },
  {
    label: "Source files",
    title: "Nothing is baked in",
    body: "Screen, camera, and audio are saved separately, so you can open any take and edit it again.",
  },
  {
    label: "Agents",
    title: "A local MCP server",
    body: "Let an agent like Claude Code or Codex read your projects and queue exports.",
  },
  {
    label: "Windows",
    title: "Windows Studio, early",
    body: "Record your screen, mic, camera, and system audio on a PC and play the take back.",
  },
  {
    label: "Updates",
    title: "Updates itself",
    body: "The app checks a signed release feed and installs new versions when you say so.",
  },
  {
    label: "Source",
    title: "Open under AGPL-3.0",
    body: "Read the code, build it yourself, or send a pull request on GitHub.",
  },
];

export function Toolbox() {
  return (
    <Section className="py-16 sm:py-24">
      <JourneySectionView area="landing" section="toolbox" payload={{ page: "home" }} />
      <div className="border-t border-separator pt-10">
        <Heading level={2} data-reveal className="max-w-[14ch]">
          Also in the app.
        </Heading>
      </div>
      <dl className="mt-10 grid gap-x-10 sm:grid-cols-2 lg:grid-cols-3">
        {items.map((item) => (
          <div key={item.title} data-reveal className="border-t border-separator py-7">
            <dt>
              <span className="label-mono text-primary/80">{item.label}</span>
              <span className="mt-3 block font-display text-lg font-bold tracking-[-0.01em]">{item.title}</span>
            </dt>
            <dd className="mt-2 text-[15px] leading-6 text-muted-foreground">{item.body}</dd>
          </div>
        ))}
      </dl>
    </Section>
  );
}

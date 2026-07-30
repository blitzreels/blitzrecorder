import { Check, Close } from "@/components/site/icons";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { Heading, Paragraph } from "@/components/ui/typography";
import { comparison } from "@/lib/content";
import { Eyebrow } from "@/components/site/landing/eyebrow";

function CompareCell({ on, highlight }: { on: boolean; highlight: boolean }) {
  return (
    <span className="flex justify-center">
      {on ? (
        <Check className={highlight ? "size-5 text-primary" : "size-5 text-muted-foreground"} />
      ) : (
        <Close className="size-4 text-faint" />
      )}
    </span>
  );
}

export function Comparison() {
  return (
    <Section width="lg" className="py-24">
      <JourneySectionView
        area="landing"
        section="comparison"
        payload={{ page: "home" }}
      />
      <div data-reveal className="flex justify-center">
        <Eyebrow center>How it compares</Eyebrow>
      </div>
      <Heading level={2} data-reveal className="mx-auto mt-5 max-w-3xl text-center">
        Sharper than Continuity Camera.{" "}
        <span className="text-gradient">Simpler than a subscription.</span>
      </Heading>
      <Paragraph data-reveal className="mx-auto mt-6 max-w-2xl text-center">
        The iPhone records your video at full quality, not a live stream, and
        you keep every raw file. No monthly fee for any of it.
      </Paragraph>
      <div data-reveal className="mx-auto mt-12 max-w-3xl overflow-x-auto">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr>
              <th className="w-1/2 py-3 pr-4" />
              {comparison.columns.map((col) => (
                <th
                  key={col.key}
                  className={
                    "px-3 py-3 text-center font-display text-[13px] font-bold sm:text-sm " +
                    (col.key === "blitz"
                      ? "rounded-t-xl bg-primary/[0.07] text-primary"
                      : "text-muted-foreground")
                  }
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {comparison.rows.map((row) => (
              <tr key={row.label} className="border-t border-border">
                <td className="py-3.5 pr-4 text-foreground">{row.label}</td>
                {comparison.columns.map((col) => (
                  <td
                    key={col.key}
                    className={
                      "px-3 py-3.5 " + (col.key === "blitz" ? "bg-primary/[0.07]" : "")
                    }
                  >
                    <CompareCell on={row[col.key]} highlight={col.key === "blitz"} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Section>
  );
}

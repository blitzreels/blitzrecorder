import Image from "next/image";
import Link from "next/link";
import { ArrowRight, Check } from "@/components/site/icons";
import { JourneySectionView } from "@/components/site/journey-markers";
import { Section } from "@/components/ui/layout";
import { ChapterBand, ChapterHeader, chapters } from "@/components/site/landing/chapter";
import { assets } from "@/lib/assets";

export function CameraChapter() {
  return (
    <ChapterBand>
    <Section id="camera" className="scroll-mt-24 py-20 sm:py-28">
      <div className="grid gap-12 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] lg:items-center lg:gap-16">
      <JourneySectionView area="landing" section="camera" payload={{ page: "home" }} />
      <ChapterHeader
        mark={chapters.camera}
        title="Use your iPhone as the camera."
        lede="Pair with a six-digit code and frame the shot from your Mac. The iPhone records at full quality, sharper than Continuity Camera, and the file lands in your take when you stop."
        aside={
          <Link
            href="/ios"
            className="group inline-flex items-center gap-1.5 text-sm font-medium text-primary"
          >
            Join the iPhone app waitlist
            <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
          </Link>
        }
        align="stack"
      />

      <div data-reveal className="panel app-surface grid overflow-hidden rounded-card sm:grid-cols-[minmax(0,1fr)_260px]">
        <div className="relative grid min-h-[440px] place-items-center bg-background px-4 pt-14 pb-10 sm:min-h-[560px]">
          <Phone className="w-[200px]" />
          <span className="label-mono absolute top-4 left-4 text-muted-foreground">iPhone</span>
        </div>
        <div className="flex flex-col p-5 sm:p-6">
          <InspectorSection label="Pairing">
            <div className="flex gap-1">
              {"482915".split("").map((digit, index) => (
                <span
                  key={index}
                  className="grid h-10 flex-1 place-items-center rounded-inner bg-fill-control font-mono text-lg font-semibold text-foreground"
                >
                  {digit}
                </span>
              ))}
            </div>
          </InspectorSection>
          <InspectorSection label="Camera">
            <dl className="flex flex-col gap-2.5 text-[13px]">
              <InspectorRow term="Device" value="iPhone" />
              <InspectorRow term="Recording" value="On the iPhone" />
              <InspectorRow term="Preview" value="Live on the Mac" />
            </dl>
          </InspectorSection>
          <InspectorSection label="Camera file">
            <div className="flex items-center justify-between text-[13px]">
              <span className="text-muted-foreground">Full resolution</span>
              <span className="inline-flex items-center gap-1 text-primary">
                <Check className="size-3.5" strokeWidth={3} />
                On Mac
              </span>
            </div>
            <div className="mt-3 h-1 overflow-hidden rounded-full bg-fill-control">
              <div className="h-full w-full rounded-full bg-primary" />
            </div>
          </InspectorSection>
        </div>
      </div>
      </div>
    </Section>
    </ChapterBand>
  );
}

function InspectorSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <section className="border-t border-separator py-5 first:border-t-0 first:pt-0 last:pb-0">
      <h3 className="label-mono mb-3 text-faint">{label}</h3>
      {children}
    </section>
  );
}

function InspectorRow({ term, value }: { term: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <dt className="text-faint">{term}</dt>
      <dd className="text-foreground">{value}</dd>
    </div>
  );
}

export function Phone({ className }: { className: string }) {
  return (
    <div className={`relative shrink-0 ${className}`}>
    <div className="relative rounded-[36px] bg-[#2a2a2c] p-[3px] shadow-[0_0_0_1px_var(--border),0_30px_70px_-30px_rgb(0_0_0/90%)]">
      <div className="relative aspect-[9/19.5] overflow-hidden rounded-[33px] bg-black">
        <Image
          src={assets.cameraTake}
          alt="The iPhone viewfinder in BlitzRecorder Camera"
          fill
          sizes="190px"
          className="object-cover object-[50%_40%]"
        />
        <div className="absolute inset-x-0 top-2.5 mx-auto h-5 w-[34%] rounded-full bg-black" />
        <div className="absolute inset-x-3 top-10 flex justify-center">
          <span className="rounded-full bg-black/55 px-2.5 py-1 text-[10px] font-medium text-white/90 backdrop-blur">
            Connected to Mac
          </span>
        </div>
        <div className="absolute inset-x-0 bottom-5 flex flex-col items-center gap-2.5">
          <span className="rounded-[4px] bg-record px-1.5 py-0.5 font-mono text-[10px] font-semibold text-white">
            00:21
          </span>
          <span className="grid size-11 place-items-center rounded-full border-[3px] border-white/90">
            <span className="size-4 rounded-[4px] bg-record" />
          </span>
        </div>
      </div>
    </div>
    </div>
  );
}

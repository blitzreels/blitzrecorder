import { IPhone, ScreenVideo } from "@/components/site/devices";
import { LandingSection } from "@/components/site/landing/landing-section";
import { realVideos } from "@/lib/assets";

const shorts = [
  { video: realVideos.shortTutorial, caption: "Tutorial", label: "A tutorial Short: the X app on top, the presenter below" },
  { video: realVideos.shortTalk, caption: "Talking head", label: "A talking-head Short filmed at a desk" },
  { video: realVideos.shortSplit, caption: "Product demo", label: "A product demo Short: Search Console on top, the presenter below" },
]

/** Proof that matters to a creator: what comes out of the app, untouched. */
export function MadeWith() {
  return (
    <LandingSection
      id="made-with"
      section="made_with"
      title="Shorts that look pro, made in one app."
      intro="A tutorial, a talking head and a product demo by Virgile, who builds BlitzRecorder. Exported straight out of the app."
      action={null}
    >
      <ul className="-mx-4 flex snap-x snap-mandatory gap-6 overflow-x-auto px-4 pb-4 [scrollbar-width:none] sm:mx-0 sm:grid sm:grid-cols-3 sm:overflow-visible sm:px-0 sm:pb-0">
        {shorts.map((short) => (
          <li key={short.caption} className="flex shrink-0 snap-center flex-col items-center">
            <IPhone className="w-[min(280px,62vw)] sm:w-full sm:max-w-[280px]">
              <ScreenVideo src={short.video.src} poster={short.video.poster} label={short.label} className="" />
            </IPhone>
            <p className="mt-5 text-[15px] font-medium text-muted-foreground">{short.caption}</p>
          </li>
        ))}
      </ul>
    </LandingSection>
  );
}

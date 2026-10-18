import { NotifyForm } from "@/components/site/notify-form";
import { LandingSection } from "@/components/site/landing/landing-section";
import { IPhone, ScreenVideo } from "@/components/site/devices";
import { realVideos } from "@/lib/assets";

export function CameraChapter() {
  return (
    <LandingSection
      id="camera"
      section="camera"
      title="Look sharp with the iPhone you already own."
      intro="Full-quality video from your iPhone, framed from your Mac. The iPhone app is in testing now."
      action={<NotifyForm source="ios_beta_home" cta="Tell me when it's out" success="You're on the list. We'll email you once." />}
    >
      <div className="grid place-items-center">
        <Phone className="w-[min(280px,64vw)]" />
      </div>
    </LandingSection>
  );
}

/** BlitzRecorder Camera on an iPhone: the live viewfinder with the Mac link and the record control. */
export function Phone({ className }: { className: string }) {
  return (
    <IPhone className={className}>
      <ScreenVideo src={realVideos.shortTalk.src} poster={realVideos.shortTalk.poster}
        label="The iPhone viewfinder in BlitzRecorder Camera" className="" />
      <div className="absolute inset-x-3 top-[9%] flex justify-center">
        <span className="rounded-full bg-black/55 px-2.5 py-1 text-[10px] font-medium text-white/90 backdrop-blur">
          Connected to Mac
        </span>
      </div>
      <div className="absolute inset-x-0 bottom-[5%] flex flex-col items-center gap-2.5">
        <span className="grid size-11 place-items-center rounded-full border-[3px] border-white/90">
          <span className="size-4 rounded-[4px] bg-record" />
        </span>
      </div>
    </IPhone>
  );
}

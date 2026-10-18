import Image from "next/image";
import { JourneySectionView } from "@/components/site/journey-markers";
import { GetApp } from "@/components/site/landing/get-app";
import { Section } from "@/components/ui/layout";
import { assets } from "@/lib/assets";

export function Closing() {
  return (
    <Section width="page" className="flex flex-col items-center py-16 text-center sm:py-24">
      <JourneySectionView area="landing" section="closing" payload={{ page: "home" }} />
      <Image src={assets.macIcon} alt="" width={96} height={96} className="size-20 rounded-[22.5%] sm:size-24" />
      <h2 className="type-hero mt-8 max-w-[14ch] text-[clamp(2.5rem,5.6vw,4.75rem)]">
        Your next video, ready to post today.
      </h2>
      <div className="mt-10">
        <GetApp source="home_closing" align="center" />
      </div>
    </Section>
  );
}

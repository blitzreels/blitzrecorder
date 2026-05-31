import React from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

const assets = {
  iosIcon: new URL("../generated-icons/nano-folded-lens-ios.png", import.meta.url).href,
  macIcon: new URL("../generated-icons/nano-folded-capture-macos.png", import.meta.url).href,
  iosPhone: new URL("../generated-screens/ios-camera-live.png", import.meta.url).href,
  macRecorder: new URL("../generated-screens/macos-recorder-live.png", import.meta.url).href,
  macIphone: new URL("../generated-screens/macos-iphone-live.png", import.meta.url).href,
  macPlan: new URL("../generated-screens/macos-plan-live.png", import.meta.url).href,
};

const landingStrip = [
  "ScreenCaptureKit",
  "Clean source files",
  "iPhone camera",
  "System audio",
  "Shorts 9:16",
  "YouTube 16:9",
];

const pages = {
  ios: {
    key: "ios",
    eyebrow: "iOS companion app",
    appName: "BlitzRecorder Camera",
    tagline: "iPhone camera for Mac",
    hero: "Turn your iPhone into a controllable camera source for BlitzRecorder on Mac.",
    icon: assets.iosIcon,
    previewKind: "phone",
    preview: assets.iosPhone,
    copyTitle: "Camera capture that stays connected to your Mac take.",
    copy:
      "Pair your iPhone with BlitzRecorder on Mac, preview the shot from your desk, and record the full-quality camera file on the device.",
    bullets: [
      "Pair over your local network with a simple code.",
      "Use the iPhone as a dedicated camera source.",
      "Monitor framing from the Mac while recording.",
      "Send the finished camera file back to the take.",
    ],
    screensTitle: "Four-screen App Store set",
    screens: [
      {
        title: "iPhone camera for BlitzRecorder.",
        text: "The companion app opens with a clear role: make the iPhone the camera source for the Mac recorder.",
        image: assets.iosIcon,
        kind: "icon",
      },
      {
        title: "Open the camera app.",
        text: "Launch on iPhone and keep the capture path dedicated to recording.",
        image: assets.iosPhone,
        kind: "phone",
      },
      {
        title: "Control it from the Mac.",
        text: "Monitor the phone in BlitzRecorder and adjust supported camera settings remotely.",
        image: assets.macIphone,
        kind: "desktop",
      },
      {
        title: "Keep the master file.",
        text: "The iPhone records locally, then transfers the finished file back to the Mac take.",
        image: assets.macRecorder,
        kind: "desktop",
      },
    ],
  },
  macos: {
    key: "macos",
    eyebrow: "macOS recording app",
    appName: "BlitzRecorder",
    tagline: "Mac studio with iPhone camera",
    hero: "Record screen, camera, microphone, and system audio from one focused Mac studio.",
    icon: assets.macIcon,
    previewKind: "desktop",
    preview: assets.macRecorder,
    copyTitle: "A recording studio built for creator takes, not setup drag.",
    copy:
      "Set the layout before recording, pair an iPhone as a camera source, capture Mac audio and microphone, then keep every source organized for the final export.",
    bullets: [
      "Capture screen, camera, microphone, and system audio.",
      "Frame vertical or horizontal layouts before the take starts.",
      "Pair BlitzRecorder Camera as a remote iPhone source.",
      "Recover, reveal, rename, and export finished recordings.",
    ],
    screensTitle: "Mac App Store set",
    screens: [
      {
        title: "Frame before recording.",
        text: "Build the creator layout on the live canvas before the take starts.",
        image: assets.macRecorder,
        kind: "desktop",
      },
      {
        title: "Add your iPhone camera.",
        text: "Monitor the phone from the Mac and keep camera controls close to the recording workflow.",
        image: assets.macIphone,
        kind: "desktop",
      },
      {
        title: "Choose the recording plan.",
        text: "Pick the format, keep sources recoverable, and move faster from capture to export.",
        image: assets.macPlan,
        kind: "desktop",
      },
    ],
  },
};

const legalPages = {
  terms: {
    eyebrow: "Effective May 22, 2026",
    title: "Terms of Use",
    intro:
      "These terms apply to BlitzRecorder and BlitzRecorder Camera. App Store downloads are also governed by Apple media services terms and the standard Apple licensed application end user license agreement unless a custom license is published.",
    sections: [
      {
        title: "Product",
        body:
          "BlitzRecorder is a macOS recording app for creating screen, camera, and audio recordings. BlitzRecorder Camera is an iPhone companion that pairs with BlitzRecorder on Mac for remote camera preview, camera controls, local iPhone camera recording, and transfer back to the Mac take.",
      },
      {
        title: "Subscription",
        body:
          "BlitzRecorder includes 3 free exports. BlitzRecorder Pro is offered through App Store subscriptions at $7.99 per month or $49.99 per year and unlocks unlimited exports while the subscription is active. Apple handles billing, renewal, cancellation, refunds, and subscription management.",
      },
      {
        title: "BlitzReels subscriber access",
        body:
          "Eligible active BlitzReels subscribers may receive included BlitzRecorder Pro access by signing in with BlitzReels. This access is tied to an active BlitzReels subscription and may change if that subscription is cancelled, expires, or becomes ineligible.",
      },
      {
        title: "User content",
        body:
          "You are responsible for the recordings you create, store, publish, or share. You must have the rights and permissions needed to record screens, voices, video, music, meetings, software, or other content.",
      },
      {
        title: "Acceptable use",
        body:
          "Do not use BlitzRecorder to violate laws, infringe rights, capture content without required consent, bypass technical protections, or create harmful or abusive material.",
      },
      {
        title: "Support",
        body:
          "Support information is available on the support page. Questions about these terms can be sent to support@blitzreels.com.",
      },
    ],
  },
  privacy: {
    eyebrow: "Effective May 22, 2026",
    title: "Privacy Policy",
    intro:
      "This policy describes how BlitzRecorder and the BlitzRecorder Camera companion app handle information.",
    sections: [
      {
        title: "Recording content",
        body:
          "BlitzRecorder records the sources you choose, such as screen video, microphone audio, system audio, local camera video, and paired iPhone camera video. Recording files are created on your devices and saved to the output folder you select.",
      },
      {
        title: "iPhone companion data",
        body:
          "BlitzRecorder Camera uses the local network to pair with your Mac, stream a monitor preview, receive camera controls, and transfer the recorded camera file back to the Mac.",
      },
      {
        title: "Account and subscription checks",
        body:
          "BlitzRecorder uses StoreKit to check App Store subscription status. If you sign in with BlitzReels, the app stores the returned access token in the macOS Keychain and sends it to the BlitzReels entitlement endpoint to verify access.",
      },
      {
        title: "Permissions",
        body:
          "The apps request permissions needed for their features: screen recording, camera, microphone, local network access, speech recognition, and user-selected file access.",
      },
      {
        title: "Data sharing",
        body:
          "We do not sell personal information. App Store purchases are handled by Apple. BlitzReels entitlement verification is handled by BlitzReels systems.",
      },
      {
        title: "Contact",
        body: "Questions about privacy can be sent to support@blitzreels.com.",
      },
    ],
  },
  support: {
    eyebrow: "Help and setup",
    title: "Support",
    intro:
      "BlitzRecorder runs on macOS and pairs with the BlitzRecorder Camera iPhone companion over your local network.",
    sections: [
      {
        title: "Pair an iPhone camera",
        body:
          "Open BlitzRecorder Camera on your iPhone, keep it on the same local network as your Mac, choose the iPhone in BlitzRecorder, and enter the six-digit code shown on the phone.",
      },
      {
        title: "Subscription and free exports",
        body:
          "BlitzRecorder includes 3 free exports. After the free exports are used, subscribe to BlitzRecorder Pro in the app for unlimited exports. Eligible BlitzReels subscribers can sign in from the app to unlock included access.",
      },
      {
        title: "Permissions",
        body:
          "If recording or pairing does not work, check macOS and iOS Settings for screen recording, camera, microphone, speech recognition, local network, and file access permissions.",
      },
      {
        title: "Contact",
        body:
          "Email support@blitzreels.com. Include your macOS version, iOS version, app version, device model, and a short description of the recording or pairing issue.",
      },
    ],
  },
};

function getInitialPage() {
  const path = window.location.pathname;
  if (path.includes("brand-guidelines")) return "hub";
  if (path.includes("ios-app-store") || path === "/ios") return "ios";
  if (path.includes("macos-app-store") || path === "/macos") return "macos";
  if (path.includes("terms")) return "terms";
  if (path.includes("privacy")) return "privacy";
  if (path.includes("support")) return "support";
  return "landing";
}

function App() {
  const initialPage = getInitialPage();
  if (initialPage === "landing") return <LandingPage />;
  if (initialPage === "hub") return <Hub />;
  if (legalPages[initialPage]) return <LegalPage page={legalPages[initialPage]} />;
  return <ProductPage page={pages[initialPage]} />;
}

function LandingPage() {
  return (
    <div className="min-h-screen overflow-x-hidden bg-[#050807] text-[#f5fbf8] antialiased">
      <Backdrop />
      <LandingNav />
      <main>
        <section className="mx-auto grid min-h-screen w-[min(1220px,calc(100%-28px))] place-items-center pt-28 pb-12 text-center">
          <div className="w-full">
            <p className="mx-auto mb-5 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.055] px-4 py-2 text-sm font-semibold text-[#afc0ba]">
              <span className="h-2 w-2 rounded-full bg-[#63f2b1] shadow-[0_0_18px_rgba(99,242,177,0.9)]" />
              Native Mac recorder · iPhone camera companion
            </p>
            <h1 className="mx-auto max-w-5xl text-balance text-5xl font-black leading-[0.95] tracking-normal sm:text-7xl lg:text-8xl">
              Record on Mac.
              <br />
              Keep every source clean.
            </h1>
            <p className="mx-auto mt-7 max-w-2xl text-balance text-lg leading-8 text-[#afc0ba] sm:text-xl">
              Capture screen, microphone, system audio, and iPhone camera as organized sources for demos, tutorials, lessons, and short-form exports.
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-4">
              <a className="inline-flex h-14 items-center justify-center rounded-full bg-[#63f2b1] px-7 font-bold text-[#03130d] no-underline shadow-[0_18px_60px_-24px_rgba(99,242,177,0.9)] transition hover:bg-[#9dffd4]" href="#pricing">
                See launch pricing
              </a>
              <a className="inline-flex h-14 items-center justify-center rounded-full border border-white/15 bg-white/[0.045] px-7 font-semibold text-white no-underline transition hover:bg-white/10" href="#workflow">
                See workflow
              </a>
            </div>
            <p className="mt-5 text-sm text-[#71847d]">Private beta · 3 trial exports · Pro $7/mo · Lifetime launch option</p>

            <div className="mx-auto mt-14 max-w-5xl">
              <div className="rounded-[24px] border border-white/10 bg-[#0b1210] p-2 shadow-[0_44px_120px_-50px_rgba(0,0,0,0.95),0_0_56px_-36px_rgba(99,242,177,0.8)]">
                <div className="flex gap-2 px-3 py-2" aria-hidden="true">
                  <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
                  <span className="h-3 w-3 rounded-full bg-[#ffbd2e]" />
                  <span className="h-3 w-3 rounded-full bg-[#28c840]" />
                </div>
                <img className="aspect-[1200/820] w-full rounded-2xl object-cover object-top" src={assets.macRecorder} alt="BlitzRecorder recording studio on macOS" />
              </div>
            </div>
          </div>
        </section>

        <section className="border-y border-white/10 py-5">
          <div className="mx-auto flex w-max animate-[br-marquee_32s_linear_infinite] items-center gap-8 text-sm font-semibold text-[#afc0ba]">
            {[...landingStrip, ...landingStrip].map((item, index) => (
              <span className="flex items-center gap-8" key={`${item}-${index}`}>
                {item}
                <i className="h-1.5 w-1.5 rounded-full bg-[#63f2b1]/70" />
              </span>
            ))}
          </div>
        </section>

        <section className="relative min-h-screen overflow-hidden" id="sources">
          <img className="absolute inset-0 h-full w-full scale-110 object-cover opacity-[0.13]" src={assets.macRecorder} alt="" />
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent,rgba(0,0,0,0.88)_72%),linear-gradient(180deg,rgba(5,8,7,0.92),rgba(5,8,7,0.18)_42%,rgba(5,8,7,0.94))]" />
          <div className="relative mx-auto grid min-h-screen w-[min(900px,calc(100%-28px))] place-items-center py-24 text-center">
            <div>
              <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">Built for editing</p>
              <h2 className="text-balance text-4xl font-black leading-none sm:text-6xl lg:text-7xl">
                One recording.
                <br />
                <span className="text-[#9dffd4]">Clean source files.</span>
              </h2>
              <p className="mx-auto mt-6 max-w-2xl text-lg leading-8 text-[#afc0ba]">
                Screen, camera, microphone, and Mac audio stay organized as separate files. Rework a crop, adjust voice, or finish the edit without recording again.
              </p>
              <ul className="mt-9 flex flex-wrap justify-center gap-3 text-sm text-[#afc0ba]">
                {["screen.mov", "camera.mov", "audio.m4a", "system.m4a", "transcript.txt"].map((file) => (
                  <li className="rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 font-mono" key={file}>{file}</li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        <section className="mx-auto grid w-[min(1180px,calc(100%-28px))] grid-cols-1 items-center gap-12 py-24 lg:grid-cols-[0.9fr_1.1fr]" id="iphone">
          <div className="mx-auto w-[min(330px,78vw)] rounded-[44px] border border-white/15 bg-white/[0.045] p-3 shadow-2xl">
            <img className="rounded-[32px]" src={assets.iosPhone} alt="BlitzRecorder Camera iPhone companion app" />
          </div>
          <div>
            <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">iPhone camera companion</p>
            <h2 className="text-balance text-4xl font-black leading-none sm:text-6xl">
              Use your iPhone as a dedicated recording camera.
            </h2>
            <p className="mt-6 max-w-xl text-lg leading-8 text-[#afc0ba]">
              Pair the companion app locally, no account needed. The iPhone records the high-quality camera file and sends it back to the Mac take when recording is done.
            </p>
            <ul className="mt-8 grid gap-3 text-lg">
              <CheckItem>Local pairing over the network</CheckItem>
              <CheckItem>Camera master recorded on the iPhone</CheckItem>
              <CheckItem>Preview and supported controls from the Mac</CheckItem>
            </ul>
          </div>
        </section>

        <section className="mx-auto w-[min(1180px,calc(100%-28px))] py-20" id="workflow">
          <div className="mx-auto max-w-3xl text-center">
            <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">Product workflow</p>
            <h2 className="text-balance text-4xl font-black leading-none sm:text-6xl">Designed for repeatable takes.</h2>
          </div>
          <div className="mt-12 grid gap-4 lg:grid-cols-3">
            <FeatureCard title="Frame before recording" image={assets.macPlan}>
              Pick vertical or horizontal layouts before the take starts, then keep source files available for export.
            </FeatureCard>
            <FeatureCard title="Camera controls on Mac" image={assets.macIphone}>
              Keep phone preview, framing, and supported camera controls close to the recorder.
            </FeatureCard>
            <FeatureCard title="Finish without cloud drag" image={assets.macRecorder}>
              Export a finished take or keep every source organized for the next edit in BlitzReels.
            </FeatureCard>
          </div>
        </section>

        <section className="mx-auto w-[min(1180px,calc(100%-28px))] py-20" id="pricing">
          <div className="mx-auto max-w-4xl text-center">
            <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">Launch pricing</p>
            <h2 className="text-balance text-4xl font-black leading-none sm:text-6xl">
              Start free. Upgrade when it becomes a workflow.
            </h2>
          </div>
          <div className="mt-12 grid gap-4 lg:grid-cols-3">
            <Plan name="Trial" price="$0" note="For testing the full recorder flow" cta="Request access">
              <CheckItem>3 finished exports</CheckItem>
              <CheckItem>All capture sources</CheckItem>
              <CheckItem>iPhone camera companion</CheckItem>
            </Plan>
            <Plan featured name="Pro monthly" price="$7" suffix="/mo" note="Unlimited finished exports" cta="Request access">
              <CheckItem>Unlimited HEVC exports</CheckItem>
              <CheckItem>Pause, resume, and PiP export</CheckItem>
              <CheckItem>Local titles and transcripts</CheckItem>
              <CheckItem>Wireless iPhone camera source</CheckItem>
            </Plan>
            <Plan name="Lifetime" price="$49" suffix=" one-time" note="Launch offer for early buyers" cta="Join launch list">
              <CheckItem>Everything in Pro monthly</CheckItem>
              <CheckItem>No recurring subscription</CheckItem>
              <CheckItem>Included for eligible BlitzReels subscribers</CheckItem>
            </Plan>
          </div>
        </section>

        <section className="mx-auto grid w-[min(900px,calc(100%-28px))] place-items-center py-28 text-center">
          <img className="h-24 w-24 rounded-[24%] object-cover shadow-[0_0_64px_-24px_rgba(99,242,177,0.9)]" src={assets.macIcon} alt="" />
          <h2 className="mt-8 text-balance text-4xl font-black leading-none sm:text-6xl">
            Record the next take without rebuilding the edit.
          </h2>
          <a className="mt-9 inline-flex h-14 items-center justify-center rounded-full bg-[#63f2b1] px-7 font-bold text-[#03130d] no-underline transition hover:bg-[#9dffd4]" href="#pricing">
            See launch pricing
          </a>
        </section>
      </main>
      <LandingFooter />
    </div>
  );
}

function LandingNav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-white/10 bg-[#050807]/75 px-4 py-3 backdrop-blur-xl">
      <div className="mx-auto flex w-[min(1220px,100%)] items-center gap-5">
        <a className="flex items-center gap-3 font-semibold no-underline" href="/">
          <img className="h-8 w-8 rounded-[24%] object-cover" src={assets.macIcon} alt="" />
          <span>BlitzRecorder</span>
        </a>
        <nav className="ml-auto hidden items-center gap-7 text-sm font-semibold text-[#afc0ba] md:flex" aria-label="Sections">
          <a className="hover:text-white" href="#sources">Sources</a>
          <a className="hover:text-white" href="#iphone">iPhone</a>
          <a className="hover:text-white" href="#workflow">Workflow</a>
          <a className="hover:text-white" href="/macos">macOS</a>
          <a className="hover:text-white" href="/ios">iOS</a>
          <a className="hover:text-white" href="/brand-guidelines">Brand</a>
          <a className="hover:text-white" href="#pricing">Pricing</a>
        </nav>
        <a className="ml-auto inline-flex h-10 items-center justify-center rounded-full bg-[#63f2b1] px-4 text-sm font-bold text-[#03130d] no-underline md:ml-0" href="#pricing">
          Pricing
        </a>
      </div>
    </header>
  );
}

function FeatureCard({ title, image, children }) {
  return (
    <article className="overflow-hidden rounded-[24px] border border-white/10 bg-white/[0.045] transition hover:-translate-y-1 hover:border-[#63f2b1]/40">
      <img className="aspect-[1200/820] w-full object-cover object-top" src={image} alt="" />
      <div className="p-6">
        <h3 className="text-2xl font-black leading-tight">{title}</h3>
        <p className="mt-3 leading-7 text-[#afc0ba]">{children}</p>
      </div>
    </article>
  );
}

function Plan({ name, price, suffix = "", note, cta, featured = false, children }) {
  return (
    <article className={["relative flex min-h-[430px] flex-col rounded-[24px] border p-7", featured ? "border-[#63f2b1]/45 bg-[#63f2b1]/[0.055] shadow-[0_32px_90px_-60px_rgba(99,242,177,0.9)]" : "border-white/10 bg-white/[0.045]"].join(" ")}>
      {featured ? <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-[#63f2b1] px-4 py-1 text-xs font-black text-[#03130d]">Best first</span> : null}
      <h3 className="text-lg font-bold text-[#afc0ba]">{name}</h3>
      <p className="mt-3 text-5xl font-black">
        {price}
        {suffix ? <small className="ml-1 text-base font-semibold text-[#afc0ba]">{suffix}</small> : null}
      </p>
      <p className="mt-2 text-sm font-semibold text-[#63f2b1]">{note}</p>
      <ul className="mt-7 grid gap-3">{children}</ul>
      <a className={["mt-auto inline-flex h-12 items-center justify-center rounded-full px-5 font-bold no-underline transition", featured ? "bg-[#63f2b1] text-[#03130d] hover:bg-[#9dffd4]" : "border border-white/15 bg-white/[0.055] text-white hover:bg-white/10"].join(" ")} href="mailto:support@blitzreels.com?subject=BlitzRecorder%20early%20access">
        {cta}
      </a>
    </article>
  );
}

function CheckItem({ children }) {
  return (
    <li className="relative list-none pl-7 text-[#f5fbf8] before:absolute before:left-0 before:top-[0.55em] before:h-2 before:w-4 before:-rotate-45 before:border-b-2 before:border-l-2 before:border-[#63f2b1]">
      {children}
    </li>
  );
}

function LandingFooter() {
  return (
    <footer className="border-t border-white/10 px-4 py-10 text-sm text-[#71847d]">
      <div className="mx-auto flex w-[min(1220px,100%)] flex-wrap items-center gap-5">
        <a className="flex items-center gap-2 font-semibold text-white no-underline" href="/">
          <img className="h-7 w-7 rounded-[24%]" src={assets.macIcon} alt="" />
          BlitzRecorder
        </a>
        <nav className="ml-auto flex flex-wrap gap-5">
          <a className="hover:text-white" href="/support">Support</a>
          <a className="hover:text-white" href="/privacy">Privacy</a>
          <a className="hover:text-white" href="/terms">Terms</a>
          <a className="hover:text-white" href="https://blitzreels.com">BlitzReels</a>
        </nav>
        <p className="basis-full">© 2026 Algomax · Strasbourg</p>
      </div>
    </footer>
  );
}

function LegalPage({ page }) {
  return (
    <div className="min-h-screen bg-[#050807] text-[#f5fbf8] antialiased">
      <Backdrop />
      <LandingNav />
      <main className="mx-auto w-[min(900px,calc(100%-28px))] pt-36 pb-20">
        <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">{page.eyebrow}</p>
        <h1 className="text-5xl font-black leading-none sm:text-7xl">{page.title}</h1>
        <p className="mt-6 max-w-3xl text-xl leading-8 text-[#afc0ba]">{page.intro}</p>
        <div className="mt-12 grid gap-8 border-t border-white/10 pt-10">
          {page.sections.map((section) => (
            <section className="grid gap-3 border-b border-white/10 pb-8" key={section.title}>
              <h2 className="text-2xl font-black">{section.title}</h2>
              <p className="text-lg leading-8 text-[#afc0ba]">{section.body}</p>
            </section>
          ))}
        </div>
      </main>
      <LandingFooter />
    </div>
  );
}

function Shell({ children, active }) {
  return (
    <div className="min-h-screen overflow-x-hidden bg-[#08110f] text-[#f5fbf8] antialiased">
      <Backdrop />
      <header className="sticky top-0 z-30 mx-auto flex w-[min(1240px,calc(100%-28px))] items-center justify-between gap-4 border-b border-white/10 bg-[#08110f]/80 py-4 backdrop-blur-xl max-sm:flex-col max-sm:items-stretch">
        <a className="flex items-center gap-3 font-semibold no-underline" href="/brand-guidelines">
          <img className="h-9 w-9 rounded-[10px] object-cover" src={assets.macIcon} alt="" />
          <span>BlitzRecorder</span>
        </a>
        <nav className="grid grid-cols-2 gap-1 rounded-full border border-white/10 bg-white/5 p-1 text-sm font-semibold max-sm:w-full" aria-label="App pages">
          <NavPill href="/ios" active={active === "ios"}>
            iOS
          </NavPill>
          <NavPill href="/macos" active={active === "macos"}>
            macOS
          </NavPill>
        </nav>
      </header>
      {children}
    </div>
  );
}

function NavPill({ href, active, children }) {
  return (
    <a
      className={[
        "flex min-h-10 min-w-20 items-center justify-center rounded-full px-5 no-underline transition",
        active ? "bg-[#f5fbf8] text-[#08110f]" : "text-[#afc0ba] hover:bg-white/10 hover:text-white",
      ].join(" ")}
      href={href}
      aria-current={active ? "page" : undefined}
    >
      {children}
    </a>
  );
}

function Backdrop() {
  return (
    <div className="pointer-events-none fixed inset-0 -z-10">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_15%_18%,rgba(80,255,176,0.14),transparent_34rem),radial-gradient(circle_at_88%_20%,rgba(114,169,255,0.16),transparent_30rem),linear-gradient(135deg,rgba(99,242,177,0.07),transparent_42%)]" />
      <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.032)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.028)_1px,transparent_1px)] bg-[size:72px_72px] [mask-image:linear-gradient(to_bottom,black,transparent_80%)]" />
    </div>
  );
}

function Hub() {
  return (
    <Shell active="">
      <main className="mx-auto grid min-h-[calc(100vh-73px)] w-[min(1040px,calc(100%-28px))] content-center gap-8 py-16">
        <section className="max-w-3xl">
          <p className="mb-3 text-sm font-black uppercase text-[#63f2b1]">BlitzRecorder</p>
          <h1 className="mb-5 text-5xl font-black leading-none sm:text-7xl lg:text-8xl">App Store pages</h1>
          <p className="max-w-2xl text-xl leading-snug text-[#afc0ba]">
            Two focused directions using the selected generated logos: Folded Lens for the iOS companion and Folded Capture for the Mac recorder.
          </p>
        </section>

        <section className="grid gap-4 md:grid-cols-2" aria-label="Split pages">
          <HubCard href="/ios" icon={assets.iosIcon} label="iOS app" sublabel="BlitzRecorder Camera" />
          <HubCard href="/macos" icon={assets.macIcon} label="macOS app" sublabel="BlitzRecorder" />
        </section>
      </main>
    </Shell>
  );
}

function HubCard({ href, icon, label, sublabel }) {
  return (
    <a className="group grid min-h-56 grid-cols-[auto_1fr] items-center gap-5 rounded-[28px] border border-white/10 bg-white/[0.055] p-6 shadow-2xl no-underline transition hover:border-white/25 hover:bg-white/[0.08] max-sm:grid-cols-1" href={href}>
      <img className="h-28 w-28 rounded-[24%] object-cover shadow-2xl transition group-hover:scale-[1.03]" src={icon} alt="" />
      <span>
        <strong className="block text-4xl font-black leading-none sm:text-5xl">{label}</strong>
        <small className="mt-2 block text-lg text-[#afc0ba]">{sublabel}</small>
      </span>
    </a>
  );
}

function ProductPage({ page }) {
  return (
    <Shell active={page.key}>
      <main>
        <Hero page={page} />
        <CopyBlock page={page} />
        <Screens page={page} />
      </main>
      <footer className="mx-auto flex w-[min(1240px,calc(100%-28px))] items-center justify-between gap-4 border-t border-white/10 py-8 text-sm text-[#7d9189] max-sm:flex-col max-sm:items-start">
        <span>Selected logo: {page.key === "ios" ? "Folded Lens" : "Folded Capture"}</span>
        <a className="rounded-full border border-white/10 px-5 py-3 font-semibold text-white no-underline transition hover:border-white/25 hover:bg-white/10" href={page.key === "ios" ? "/macos" : "/ios"}>
          Open {page.key === "ios" ? "macOS" : "iOS"} page
        </a>
      </footer>
    </Shell>
  );
}

function Hero({ page }) {
  return (
    <section className="mx-auto grid min-h-[calc(100vh-73px)] w-[min(1240px,calc(100%-28px))] grid-cols-1 items-center gap-10 py-12 md:py-16 lg:grid-cols-[minmax(0,0.86fr)_minmax(420px,1fr)] lg:gap-16 xl:gap-24">
      <div className="min-w-0">
        <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">{page.eyebrow}</p>
        <h1 className={["mb-6 max-w-[11ch] text-5xl font-black leading-none sm:text-7xl", page.key === "ios" ? "lg:text-[112px]" : "lg:text-[88px]"].join(" ")}>
          {page.appName}
        </h1>
        <p className="mb-8 max-w-2xl text-xl leading-snug text-[#afc0ba] sm:text-2xl">{page.hero}</p>
        <StoreMeta page={page} />
      </div>

      <div className="grid min-w-0 place-items-center">
        {page.previewKind === "phone" ? <PhoneFrame src={page.preview} /> : <MacFrame src={page.preview} />}
      </div>
    </section>
  );
}

function StoreMeta({ page }) {
  return (
    <div className="grid w-full max-w-[450px] grid-cols-[auto_1fr] items-center gap-4 rounded-3xl border border-white/10 bg-white/[0.065] p-3 shadow-2xl max-[380px]:grid-cols-1">
      <img className="h-20 w-20 rounded-[24%] object-cover sm:h-24 sm:w-24" src={page.icon} alt="" />
      <div className="min-w-0">
        <strong className="block text-xl leading-tight">{page.appName}</strong>
        <span className="mt-1 block text-[#afc0ba]">{page.tagline}</span>
        <b className="mt-3 flex h-8 w-20 items-center justify-center rounded-full bg-[#63f2b1] text-xs text-[#07110d]">GET</b>
      </div>
    </div>
  );
}

function PhoneFrame({ src }) {
  return (
    <div className="w-[min(330px,78vw)] rounded-[48px] border border-white/20 bg-[#050807] p-3 shadow-2xl">
      <img className="aspect-[1320/2868] w-full rounded-[36px] object-cover" src={src} alt="iPhone app preview" />
    </div>
  );
}

function MacFrame({ src }) {
  return (
    <div className="w-full max-w-[760px] rounded-[22px] border border-white/20 bg-gradient-to-br from-[#22332f] to-[#08110f] p-3 shadow-2xl">
      <div className="flex gap-2 px-1 pb-3" aria-hidden="true">
        <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
        <span className="h-3 w-3 rounded-full bg-[#ffbd2e]" />
        <span className="h-3 w-3 rounded-full bg-[#28c840]" />
      </div>
      <img className="aspect-[1200/820] w-full rounded-xl border border-white/10 object-cover object-top" src={src} alt="Mac app preview" />
    </div>
  );
}

function CopyBlock({ page }) {
  return (
    <section className="mx-auto grid w-[min(1240px,calc(100%-28px))] grid-cols-1 gap-8 border-t border-white/10 py-16 md:grid-cols-[minmax(280px,0.82fr)_minmax(0,1fr)] lg:gap-20">
      <div>
        <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">App Store copy</p>
        <h2 className="text-4xl font-black leading-none sm:text-5xl lg:text-6xl">{page.copyTitle}</h2>
      </div>
      <div className="text-lg leading-relaxed text-[#afc0ba] sm:text-xl">
        <p className="mb-6">{page.copy}</p>
        <ul className="grid gap-0">
          {page.bullets.map((bullet) => (
            <li className="border-t border-white/10 py-3 pl-4" key={bullet}>
              {bullet}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function Screens({ page }) {
  return (
    <section className="mx-auto w-[min(1240px,calc(100%-28px))] border-t border-white/10 py-16">
      <div className="mb-6">
        <p className="mb-4 text-sm font-black uppercase text-[#63f2b1]">Preview screens</p>
        <h2 className="text-4xl font-black leading-none sm:text-5xl lg:text-6xl">{page.screensTitle}</h2>
      </div>
      <div className={["grid gap-4", page.screens.length === 4 ? "lg:grid-cols-4 md:grid-cols-2" : "lg:grid-cols-3 md:grid-cols-2"].join(" ")}>
        {page.screens.map((screen, index) => (
          <PreviewCard key={screen.title} screen={screen} index={index} />
        ))}
      </div>
    </section>
  );
}

function PreviewCard({ screen, index }) {
  const imageClass =
    screen.kind === "icon"
      ? "mx-auto mb-10 mt-4 aspect-square w-[min(220px,64%)] rounded-[24%] object-cover shadow-2xl"
      : screen.kind === "phone"
        ? "mx-auto mb-4 mt-2 h-80 w-[min(240px,calc(100%-44px))] rounded-[34px] border border-white/10 object-cover object-top"
        : "mx-3 mb-3 mt-2 h-72 w-[calc(100%-24px)] rounded-2xl border border-white/10 object-cover object-top";

  return (
    <article className="grid min-h-[520px] content-between overflow-hidden rounded-[26px] border border-white/10 bg-[radial-gradient(circle_at_50%_20%,rgba(99,242,177,0.16),transparent_18rem),linear-gradient(180deg,#1b2826,#151f1d)]">
      <div className="p-6 pb-3">
        <span className="mb-4 block text-sm font-black text-[#f6c86d]">{String(index + 1).padStart(2, "0")}</span>
        <h3 className="mb-3 text-3xl font-black leading-tight">{screen.title}</h3>
        <p className="text-[#afc0ba]">{screen.text}</p>
      </div>
      <img className={imageClass} src={screen.image} alt="" />
    </article>
  );
}

createRoot(document.getElementById("root")).render(<App />);

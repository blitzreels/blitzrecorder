import React from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

const assets = {
  iosIcon: "generated-icons/nano-folded-lens-ios.png",
  macIcon: "generated-icons/nano-folded-capture-macos.png",
  iosPhone: "generated-screens/ios-camera-live.png",
  macRecorder: "generated-screens/macos-recorder-live.png",
  macIphone: "generated-screens/macos-iphone-live.png",
  macPlan: "generated-screens/macos-plan-live.png",
};

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

function getInitialPage() {
  const path = window.location.pathname;
  if (path.includes("ios-app-store")) return "ios";
  if (path.includes("macos-app-store")) return "macos";
  return "hub";
}

function App() {
  const initialPage = getInitialPage();
  if (initialPage === "hub") return <Hub />;
  return <ProductPage page={pages[initialPage]} />;
}

function Shell({ children, active }) {
  return (
    <div className="min-h-screen overflow-x-hidden bg-[#08110f] text-[#f5fbf8] antialiased">
      <Backdrop />
      <header className="sticky top-0 z-30 mx-auto flex w-[min(1240px,calc(100%-28px))] items-center justify-between gap-4 border-b border-white/10 bg-[#08110f]/80 py-4 backdrop-blur-xl max-sm:flex-col max-sm:items-stretch">
        <a className="flex items-center gap-3 font-semibold no-underline" href="brand-guidelines.html">
          <img className="h-9 w-9 rounded-[10px] object-cover" src={assets.macIcon} alt="" />
          <span>BlitzRecorder</span>
        </a>
        <nav className="grid grid-cols-2 gap-1 rounded-full border border-white/10 bg-white/5 p-1 text-sm font-semibold max-sm:w-full" aria-label="App pages">
          <NavPill href="ios-app-store.html" active={active === "ios"}>
            iOS
          </NavPill>
          <NavPill href="macos-app-store.html" active={active === "macos"}>
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
          <HubCard href="ios-app-store.html" icon={assets.iosIcon} label="iOS app" sublabel="BlitzRecorder Camera" />
          <HubCard href="macos-app-store.html" icon={assets.macIcon} label="macOS app" sublabel="BlitzRecorder" />
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
        <a className="rounded-full border border-white/10 px-5 py-3 font-semibold text-white no-underline transition hover:border-white/25 hover:bg-white/10" href={page.key === "ios" ? "macos-app-store.html" : "ios-app-store.html"}>
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

import type { StaticImageData } from "next/image";
import { assets } from "@/lib/assets";

export const ALGOMAX_URL = "https://algomax.fr";

export const requirements = {
  macos: "macOS 15 Sequoia or later",
  ios: "iOS 18 or later",
};

/** Shown next to the Mac download. The DMG is a universal build. */
export const macCompatibility = "macOS 15 Sequoia or later · Apple silicon and Intel";

export type FeatureIconKey =
  | "composite"
  | "scenes"
  | "background"
  | "remote"
  | "aspect"
  | "sources"
  | "timeline"
  | "silence";

export const studioBeats: { title: string; body: string }[] = [
  {
    title: "Screen, window, or area",
    body: "Mic and system audio in the same take.",
  },
  {
    title: "Timeline in the same app",
    body: "Waveforms, cuts, and layout after you stop.",
  },
  {
    title: "Silence cuts",
    body: "Drop the pauses so the take is short-form ready.",
  },
  {
    title: "Local files",
    body: "Keep the recording on your Mac. AGPL source.",
  },
];

export type FaqItem = { q: string; a: string };

export const faqs: FaqItem[] = [
  {
    q: "Do I need an account or license key?",
    a: "No. BlitzRecorder 0.15 and later includes recording, editing, 4K export, 60 fps export, and iPhone camera support without an account, email, or license key. Capture options depend on your hardware.",
  },
  {
    q: "Is it open source?",
    a: "Yes. AGPL. Download the Mac app from this site. No account, card, watermark, or subscription.",
  },
  {
    q: "Is my footage private?",
    a: "Yes. Recording stays on your Mac, in a folder you choose. The native apps do not include an analytics SDK.",
  },
  {
    q: "What's BlitzReels?",
    a: "Clips, captions, and publish, from the same company. Recorder is the local Mac studio for the take.",
  },
];

export const license = {
  features: [
    "4K export",
    "60 fps export",
    "Optional iPhone camera",
    "No account or license key",
    "No watermark or subscription",
  ],
};

export type ScreenKind = "icon" | "phone" | "desktop";
export type ProductScreen = { title: string; text: string; image: StaticImageData; kind: ScreenKind };

export type ProductPageData = {
  key: "ios" | "macos";
  eyebrow: string;
  appName: string;
  tagline: string;
  hero: string;
  icon: StaticImageData;
  previewKind: "phone" | "desktop";
  preview: StaticImageData;
  copyTitle: string;
  copy: string;
  bullets: string[];
  requirement: string;
  screensTitle: string;
  screens: ProductScreen[];
};

export const pages: Record<"ios" | "macos", ProductPageData> = {
  ios: {
    key: "ios",
    eyebrow: "iPhone app",
    appName: "BlitzRecorder Camera",
    tagline: "Your iPhone, as a Mac camera",
    hero: "Use your iPhone as the camera for your Mac recordings.",
    icon: assets.iosIcon,
    previewKind: "phone",
    preview: assets.iosPhone,
    copyTitle: "Record with the phone you already have.",
    copy:
      "Open the app and pair your iPhone with your Mac. Your iPhone records locally and sends the video to your Mac when you stop. You set up the shot from your desk.",
    bullets: [
      "Pairs with your Mac in seconds. No account.",
      "Records locally on the iPhone at full quality.",
      "Set up the shot from your Mac, not the phone.",
      "Your video saves to your Mac on its own.",
    ],
    requirement: requirements.ios,
    screensTitle: "How it works",
    screens: [
      {
        title: "Your iPhone is the camera.",
        text: "The app does one thing well: it turns your iPhone into the camera for your Mac.",
        image: assets.iosIcon,
        kind: "icon",
      },
      {
        title: "Open it and you are ready.",
        text: "Start the app on your iPhone. It waits for your Mac to connect.",
        image: assets.iosPhone,
        kind: "phone",
      },
      {
        title: "Set up the shot from your Mac.",
        text: "See your iPhone on your Mac and line up the shot from your desk.",
        image: assets.macPlan,
        kind: "desktop",
      },
      {
        title: "Keep the full-quality video.",
        text: "Your iPhone records the video, then sends it to your Mac when you stop.",
        image: assets.macRecorder,
        kind: "desktop",
      },
    ],
  },
  macos: {
    key: "macos",
    eyebrow: "Mac app",
    appName: "BlitzRecorder",
    tagline: "Studio recording and editing for Mac",
    hero: "Record screen and camera, then cut the take on a timeline. iPhone camera, silence removal, local files.",
    icon: assets.macIcon,
    previewKind: "desktop",
    preview: assets.macRecorder,
    copyTitle: "Record the take. Cut it here.",
    copy:
      "Set up the shot, pick tall or wide, and hit record. Then open the take: timeline, waveforms, silence cuts, scene layouts. Raw screen, camera, and audio files stay on your Mac.",
    bullets: [
      "Record your screen, camera, mic, and Mac sound.",
      "Use your iPhone as the camera.",
      "Cut silence and layouts on a timeline.",
      "Keep the raw screen, camera, and audio files.",
    ],
    requirement: requirements.macos,
    screensTitle: "How it works",
    screens: [
      {
        title: "Set up your shot first.",
        text: "Pick a tall or wide layout on screen before you record. What you see is what you get.",
        image: assets.macRecorder,
        kind: "desktop",
      },
      {
        title: "Add your iPhone camera.",
        text: "See your iPhone on your Mac and keep the camera controls next to your recording.",
        image: assets.macPlan,
        kind: "desktop",
      },
      {
        title: "Pick how you record.",
        text: "Choose your format, keep every part saved, and move from recording to editing fast.",
        image: assets.macRecorder,
        kind: "desktop",
      },
    ],
  },
};

export type LegalSection = { title: string; body: string };
export type LegalPageData = { eyebrow: string; title: string; intro: string; sections: LegalSection[] };

export const legalPages: Record<"terms" | "privacy" | "support", LegalPageData> = {
  terms: {
    eyebrow: "Effective May 22, 2026",
    title: "Terms of Use",
    intro:
      "These terms cover BlitzRecorder and BlitzRecorder Camera. If you download from the App Store, Apple's media services terms also apply.",
    sections: [
      {
        title: "Product",
        body:
          "BlitzRecorder is a Mac app for recording your screen, camera, and audio. BlitzRecorder Camera is an iPhone app that pairs with BlitzRecorder on your Mac. It lets you preview and control the iPhone camera, record on the iPhone, and send that video back to your Mac.",
      },
      {
        title: "License",
        body:
          "The Mac app is free. Version 0.15 and later includes all features without an account or app license key. The source is available under AGPL-3.0-only. Separate commercial source licenses are available by written agreement with the copyright holder.",
      },
      {
        title: "User content",
        body:
          "You are responsible for what you record, save, publish, or share. Make sure you have the right to record the screens, voices, video, music, meetings, software, or anything else you capture.",
      },
      {
        title: "Acceptable use",
        body:
          "Do not use BlitzRecorder to break the law, infringe on someone's rights, record people without the consent you need, get around technical protections, or make harmful or abusive content.",
      },
      {
        title: "Support",
        body:
          "You can find help on the support page. For questions about these terms, email support@blitzreels.com.",
      },
    ],
  },
  privacy: {
    eyebrow: "Effective May 22, 2026",
    title: "Privacy Policy",
    intro:
      "This policy explains how BlitzRecorder and BlitzRecorder Camera handle your information.",
    sections: [
      {
        title: "Recording content",
        body:
          "BlitzRecorder records only the sources you pick, such as your screen, microphone, Mac audio, local camera, and paired iPhone camera. The files are created on your own devices and saved to the folder you choose.",
      },
      {
        title: "iPhone companion data",
        body:
          "BlitzRecorder Camera uses your local network to pair with your Mac. It sends a preview to your Mac, receives camera controls, and transfers the recorded video back to your Mac.",
      },
      {
        title: "License checks",
        body:
          "BlitzRecorder 0.15 and later does not issue or validate app license keys. If you use an older version and request a legacy key on this website, we store your email and license record. Older paid keys may still be checked against Stripe payment status. A BlitzReels account is only used when you choose its upload integration.",
      },
      {
        title: "Permissions",
        body:
          "The apps ask only for the permissions they need: screen recording, camera, microphone, local network, speech recognition, and access to files you choose.",
      },
      {
        title: "Data sharing",
        body:
          "We do not sell your personal information. Recordings stay on your devices unless you choose to share them. If you claim a license, we store the email you entered and the license record. Historical Stripe purchases keep their payment records at Stripe.",
      },
      {
        title: "Website analytics",
        body:
          "The BlitzRecorder website uses DataFast to measure page visits, license claims, and basic conversion metadata. The native Mac and iPhone apps do not include a DataFast or analytics SDK.",
      },
      {
        title: "Diagnostics and feedback",
        body:
          "BlitzRecorder does not include an analytics SDK or crash-reporting SDK. If you need help, you can copy diagnostics from the Help menu and choose what to paste into a GitHub issue or support email.",
      },
      {
        title: "Contact",
        body: "For privacy questions, email support@blitzreels.com.",
      },
    ],
  },
  support: {
    eyebrow: "Help and setup",
    title: "Support",
    intro:
      "BlitzRecorder runs on your Mac and pairs with the BlitzRecorder Camera app on your iPhone over your local network.",
    sections: [
      {
        title: "Pair an iPhone camera",
        body:
          "Open BlitzRecorder Camera on your iPhone and keep it on the same network as your Mac. In BlitzRecorder, pick your iPhone, then type the six-digit code shown on the phone.",
      },
      {
        title: "License",
        body:
          "Update to BlitzRecorder 0.15 or later to use every feature without a key. The /license page can still provide keys for older versions. If an export fails, check macOS permissions, available disk space, and whether the source media still exists.",
      },
      {
        title: "Permissions",
        body:
          "If recording or pairing does not work, open Settings on your Mac and iPhone. Check that screen recording, camera, microphone, speech recognition, local network, and file access are allowed.",
      },
      {
        title: "Contact",
        body:
          "Email support@blitzreels.com. On Mac, use Help -> Copy Diagnostics if you want to include app version, macOS version, chip architecture, permission state, and current recording settings. Diagnostics are copied to your clipboard and are not sent automatically.",
      },
    ],
  },
};

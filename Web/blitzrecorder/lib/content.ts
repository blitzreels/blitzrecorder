import type { StaticImageData } from "next/image";
import { assets } from "@/lib/assets";

export const BLITZREELS_URL =
  "https://www.blitzreels.com/?ref=blitzrecorder&source=website&placement=blitzrecorder_site";
export const ALGOMAX_URL = "https://algomax.fr";

export const requirements = {
  macos: "macOS 15 Sequoia or later",
  ios: "iOS 18 or later",
};

export const cleanOutcomes = ["Scene switches", "Optional source files", "Recovery files when needed"];

export type WorkflowCard = { title: string; image: StaticImageData; body: string };

export const workflowCards: WorkflowCard[] = [
  {
    title: "Set up the shot first",
    image: assets.macPlan,
    body: "Pick a tall or wide layout before you hit record. What you see is what you export.",
  },
  {
    title: "Make a Short and a video",
    image: assets.macIphone,
    body: "Pick vertical for Shorts or horizontal for YouTube before recording. Switch scenes during the take.",
  },
  {
    title: "Jump straight to editing",
    image: assets.macRecorder,
    body: "Export the finished video, or send the files to BlitzReels and keep editing.",
  },
];

export type Plan = {
  name: string;
  price: string;
  suffix?: string;
  subline?: string;
  save?: string;
  note: string;
  features: string[];
};

export const pricing: { trial: Plan; pro: Plan } = {
  trial: {
    name: "Trial",
    price: "$0",
    note: "Try the whole app for free",
    features: [
      "Make 10 videos for free",
      "Use your iPhone as the camera",
      "Make tall or wide videos",
      "No card needed",
    ],
  },
  pro: {
    name: "Pro",
    price: "$49.99",
    suffix: "/year",
    subline: "or $7.99/month",
    save: "Save 48%",
    note: "Export as many videos as you want",
    features: [
      "Export as many videos as you want",
      "Use full-quality iPhone recordings",
      "Keep source files when you need them",
      "Pause and pick back up while recording",
      "Add titles and captions",
    ],
  },
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
        image: assets.macIphone,
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
    tagline: "Studio recording for Mac",
    hero: "Record Mac videos with scenes, screen capture, and iPhone camera support.",
    icon: assets.macIcon,
    previewKind: "desktop",
    preview: assets.macRecorder,
    copyTitle: "Record once. Fix anything later.",
    copy:
      "Set up your shot, pick a vertical or horizontal canvas, and hit record. BlitzRecorder can keep source files when you want more control after the take.",
    bullets: [
      "Record your screen, camera, mic, and Mac sound.",
      "Use your iPhone as the camera.",
      "Set up tall or wide videos before you record.",
      "Keep source files for post-recording fixes.",
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
        image: assets.macIphone,
        kind: "desktop",
      },
      {
        title: "Pick how you record.",
        text: "Choose your format, keep every part saved, and move from recording to editing fast.",
        image: assets.macPlan,
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
        title: "Subscription",
        body:
          "BlitzRecorder includes 10 free exports. BlitzRecorder Pro is an App Store subscription that costs $7.99 per month or $49.99 per year. While it is active, you can export as many videos as you want. Apple handles billing, renewals, cancellations, and refunds.",
      },
      {
        title: "BlitzReels subscriber access",
        body:
          "If you have an active BlitzReels subscription, you may get BlitzRecorder Pro at no extra cost by signing in with BlitzReels. This access depends on your BlitzReels subscription. It can change if that subscription ends or is no longer eligible.",
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
        title: "Account and subscription checks",
        body:
          "BlitzRecorder uses Apple StoreKit to check your App Store subscription status. If you sign in with BlitzReels, the app saves the access token in your macOS Keychain and sends it to BlitzReels to confirm your access.",
      },
      {
        title: "Permissions",
        body:
          "The apps ask only for the permissions they need: screen recording, camera, microphone, local network, speech recognition, and access to files you choose.",
      },
      {
        title: "Data sharing",
        body:
          "We do not sell your personal information. Apple handles App Store purchases. BlitzReels handles checks for BlitzReels access.",
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
        title: "Subscription and free exports",
        body:
          "BlitzRecorder comes with 10 free exports. Once you use them, subscribe to BlitzRecorder Pro in the app to export as many videos as you want. If you already pay for BlitzReels, sign in from the app to unlock Pro at no extra cost.",
      },
      {
        title: "Permissions",
        body:
          "If recording or pairing does not work, open Settings on your Mac and iPhone. Check that screen recording, camera, microphone, speech recognition, local network, and file access are allowed.",
      },
      {
        title: "Contact",
        body:
          "Email support@blitzreels.com. Tell us your macOS version, iOS version, app version, device model, and a short description of the problem.",
      },
    ],
  },
};

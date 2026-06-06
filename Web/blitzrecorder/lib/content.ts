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
  | "sources";

export type FeatureItem = { icon: FeatureIconKey; title: string; body: string };

export const features: FeatureItem[] = [
  {
    icon: "composite",
    title: "Screen and camera together",
    body: "Composite your screen and camera into one frame.",
  },
  {
    icon: "scenes",
    title: "Live scene switching",
    body: "Cut or dissolve between layouts while you record.",
  },
  {
    icon: "background",
    title: "Replace your background",
    body: "Drop in a clean backdrop instead of your room.",
  },
  {
    icon: "remote",
    title: "Control the iPhone from your Mac",
    body: "Frame and adjust the camera without touching the phone.",
  },
  {
    icon: "aspect",
    title: "Vertical or horizontal",
    body: "9:16 for Shorts, 16:9 for long-form. Set it before you record.",
  },
  {
    icon: "sources",
    title: "Keep the source files",
    body: "Save screen, camera, and audio as separate files.",
  },
];

export type Setup = { title: string; image: StaticImageData; body: string };

export const setups: Setup[] = [
  {
    title: "Camera only",
    image: assets.macPlan,
    body: "Talk straight to camera for a clean face-cam take.",
  },
  {
    title: "Screen and camera",
    image: assets.macRecorder,
    body: "Stack your screen over your camera for tutorials and demos.",
  },
];

export type FaqItem = { q: string; a: string };

export const faqs: FaqItem[] = [
  {
    q: "What does the paid license include?",
    a: "A $39 beta lifetime license, planned to become $79 after launch. It unlocks the iPhone camera, 4K export, and 60 fps export in the Mac app, with updates through beta and v1.",
  },
  {
    q: "What does the free app do?",
    a: "Record your screen, Mac camera, and mic with scenes, layouts, and backgrounds, and export in 1080p. There is no account, card, watermark, or subscription requirement.",
  },
  {
    q: "Do I need an account?",
    a: "No app account is required. Checkout is handled by Stripe, then you claim a license key for the Mac app.",
  },
  {
    q: "Does it run on Intel Macs?",
    a: "Yes. It is a universal build for Apple silicon and Intel, on macOS 15 Sequoia or later.",
  },
  {
    q: "Do I have to plug in my iPhone?",
    a: "No. The iPhone pairs with your Mac over your local network. It needs iOS 18 or later.",
  },
  {
    q: "Is my footage private?",
    a: "Yes. Recording happens on your own devices and saves to a folder you choose. The native apps do not include an analytics SDK, and recordings are not uploaded.",
  },
  {
    q: "Where do I get the apps?",
    a: "Download the Mac app from blitzrecorder.com. The iPhone app is the companion camera and needs the Mac app to do useful recording work.",
  },
];

export type Plan = {
  name: string;
  price: string;
  regularPrice?: string;
  suffix?: string;
  subline?: string;
  save?: string;
  note: string;
  features: string[];
  cta: "buy" | "download";
  ctaLabel: string;
};

export const pricing: { free: Plan; early: Plan } = {
  free: {
    name: "Free",
    price: "$0",
    note: "The Mac app",
    features: [
      "Record your screen, camera, and mic",
      "Scenes, layouts, and backgrounds",
      "1080p export",
      "No account, no card",
    ],
    cta: "download",
    ctaLabel: "Download for Mac",
  },
  early: {
    name: "Lifetime License",
    price: "$39",
    regularPrice: "$79",
    suffix: " lifetime",
    subline: "Beta price before $79 launch pricing",
    save: "Save $40",
    note: "Unlocks the full studio",
    features: [
      "Use your iPhone as the camera",
      "4K export",
      "60 fps export",
      "One license for your personal Macs",
      "Updates through beta and v1",
    ],
    cta: "buy",
    ctaLabel: "Buy Lifetime License",
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
    tagline: "Studio recording for Mac",
    hero: "Record Mac videos with scenes, screen capture, and iPhone camera support.",
    icon: assets.macIcon,
    previewKind: "desktop",
    preview: assets.macRecorder,
    copyTitle: "Set up the shot, then record it.",
    copy:
      "Set up your shot, pick tall or wide, and hit record. You can keep the raw screen, camera, and audio files to use later.",
    bullets: [
      "Record your screen, camera, mic, and Mac sound.",
      "Use your iPhone as the camera.",
      "Set up tall or wide videos before you record.",
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
        title: "License",
        body:
          "The Mac app is free to download and use, including 1080p export. The paid lifetime license is handled through Stripe checkout and unlocks the iPhone camera, 4K export, and 60 fps export. After payment, Stripe redirects you to a claim page where your license key is created.",
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
          "Checkout is handled by Stripe. BlitzRecorder license validation checks the license key you provide and may verify the associated Stripe payment status. The app does not need a BlitzReels account to record.",
      },
      {
        title: "Permissions",
        body:
          "The apps ask only for the permissions they need: screen recording, camera, microphone, local network, speech recognition, and access to files you choose.",
      },
      {
        title: "Data sharing",
        body:
          "We do not sell your personal information. Recordings stay on your devices unless you choose to share them. Stripe handles checkout and payment records for license purchases.",
      },
      {
        title: "Website analytics",
        body:
          "The BlitzRecorder website uses DataFast to measure page visits, checkout starts, license claims, and basic conversion metadata. The native Mac and iPhone apps do not include a DataFast or analytics SDK.",
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
          "After buying a lifetime license, Stripe redirects you to a claim page with your license key. Enter that key in the Mac app to unlock the iPhone camera, 4K export, and 60 fps export. If an export fails, check macOS permissions, available disk space, and whether the source media still exists.",
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

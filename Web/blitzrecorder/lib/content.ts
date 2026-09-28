import type { StaticImageData } from "next/image";
import { assets } from "@/lib/assets";

export const ALGOMAX_URL = "https://algomax.fr";

export const requirements = {
  macos: "macOS 15 Sequoia or later",
  ios: "iOS 18 or later",
};

/** Shown next to the Mac download. The DMG is a universal build. */
export const macCompatibility = "macOS 15 Sequoia or later · Apple silicon and Intel";

export type FaqItem = { q: string; a: string };

export const faqs: FaqItem[] = [
  {
    q: "Do I need an account or a license key?",
    a: "No. Recording, editing, 4K and 60 fps export, transcripts, and the iPhone camera work without an account, email, or key. You only sign in to BlitzReels if you choose to send a video there.",
  },
  {
    q: "Is it really free?",
    a: "Yes. The source is public under AGPL-3.0, and the signed Mac app is a free download. There is no watermark, export limit, or subscription.",
  },
  {
    q: "Where do my recordings go?",
    a: "To a folder you choose on your Mac. Transcription runs on your Mac too. The apps include no analytics or crash-reporting SDK.",
  },
  {
    q: "Which Macs are supported?",
    a: "Any Mac with macOS 15 Sequoia or later, Apple silicon or Intel. The iPhone camera app needs iOS 18 or later.",
  },
  {
    q: "Is there a Windows version?",
    a: "Windows Studio is an early capture app. It records your screen, microphone, camera, and system audio, and plays the take back. The editor is Mac only for now. Installers are on GitHub Releases.",
  },
  {
    q: "What is BlitzReels?",
    a: "BlitzReels is the company behind BlitzRecorder. Its web app finds the best moments in a long recording, reframes them for vertical video, and adds captions. Sending a video there is optional.",
  },
];

export const freeIncludes = [
  "4K and 60 fps export",
  "iPhone as a camera",
  "On-device transcripts",
  "No watermark or export limit",
  "No account or license key",
];

export type ProductScreen = { title: string; text: string };

export type ProductPageData = {
  key: "ios" | "macos";
  eyebrow: string;
  appName: string;
  tagline: string;
  hero: string;
  icon: StaticImageData;
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
    hero: "Turn your iPhone into the studio camera for BlitzRecorder on your Mac. Full quality, framed from your desk.",
    icon: assets.iosIcon,
    copyTitle: "Record with the camera you already own.",
    copy:
      "Continuity Camera streams a compressed feed to your Mac. BlitzRecorder Camera records on the iPhone at full quality and sends a separate live preview, so you frame the shot from your desk and keep the sharp file.",
    bullets: [
      "Pairs over your local network with a six-digit code.",
      "Records the full-quality file on the iPhone.",
      "Camera controls and preview live on the Mac.",
      "The file moves into your take when you stop.",
    ],
    requirement: requirements.ios,
    screensTitle: "How it works",
    screens: [
      {
        title: "Pair once.",
        text: "Open the app on your iPhone, pick it in BlitzRecorder, and type the six-digit code.",
      },
      {
        title: "Frame it from your desk.",
        text: "A live preview and the camera controls sit next to your recording on the Mac.",
      },
      {
        title: "Keep the full-quality file.",
        text: "The iPhone records on the device and sends the file to your Mac when you stop. Interrupted transfers resume.",
      },
    ],
  },
  macos: {
    key: "macos",
    eyebrow: "Mac app",
    appName: "BlitzRecorder",
    tagline: "Record and edit on your Mac",
    hero: "Record your screen and camera together, then edit the take on a timeline. Free, open source, and local.",
    icon: assets.macIcon,
    copyTitle: "One app from the first take to the export.",
    copy:
      "Frame the shot in 9:16 or 16:9 before you press record. When you stop, the take opens on a timeline with every source on its own track, ready to cut, relayout, and export.",
    bullets: [
      "Screen, camera, microphone, and Mac audio in one take.",
      "Silence detection, text, zoom, and layouts in the editor.",
      "Transcripts with speakers, made on your Mac.",
      "Separate source files, so any take can be edited again.",
    ],
    requirement: requirements.macos,
    screensTitle: "How it works",
    screens: [
      {
        title: "Frame the shot.",
        text: "Choose your screen, window, or app, add a camera, and pick a layout. The preview is the export.",
      },
      {
        title: "Record the take.",
        text: "Switch scenes while you talk. Screen, camera, and audio are saved as separate files.",
      },
      {
        title: "Edit on the timeline.",
        text: "Remove silences, adjust crops and layouts, add text and zoom, then read the transcript.",
      },
      {
        title: "Export or send.",
        text: "Export up to 4K at 60 fps and up to 2x speed, or send the MP4 to BlitzReels for captions.",
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

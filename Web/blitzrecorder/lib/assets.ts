import iosIcon from "@/public/generated-icons/nano-folded-lens-ios.png";
import macIcon from "@/public/generated-icons/nano-folded-capture-macos.png";
import blitzreelsWordmark from "@/public/logos/blitzreels-wordmark-white.png";
import editor from "@/public/media/editor.webp";
import screenTake from "@/public/media/take-screen.jpg";
import cameraTake from "@/public/media/take-camera.jpg";
import presentationPoster from "@/public/media/blitzrecorder-film-poster.webp";
import editorExport from "@/public/media/editor-export.png";

export const assets = {
  iosIcon,
  macIcon,
  blitzreelsWordmark,
  editor,
  screenTake,
  cameraTake,
  presentationPoster,
  editorExport,
};

export const presentationFilm = "/videos/blitzrecorder-film.mp4";
/**
 * Real BlitzRecorder exports from published videos, trimmed to silent loops. `landscape` is
 * "How to Start Making Short Videos" (4K, screen and camera); the Shorts are 1080x1920 app exports.
 */
export const realVideos = {
  landscape: { src: "/videos/real-landscape.mp4", poster: "/media/real-landscape.jpg" },
  shortSplit: { src: "/videos/real-short-split.mp4", poster: "/media/real-short-split.jpg" },
  shortTalk: { src: "/videos/real-short-talk.mp4", poster: "/media/real-short-talk.jpg" },
  shortTutorial: { src: "/videos/real-short-twitter.mp4", poster: "/media/real-short-twitter.jpg" },
};

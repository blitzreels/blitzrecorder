"use client";

import { useCallback, useEffect, useEffectEvent, useRef, useState } from "react";
import type Hls from "hls.js";
import { transcriptVTT, type VideoDetails } from "@/lib/hosting/details";

type MediaState = {
  playing: boolean; ready: boolean; waiting: boolean; time: number; duration: number;
  buffered: number; volume: number; muted: boolean; speed: number; ended: boolean;
};
type WebkitVideo = HTMLVideoElement & { webkitEnterFullscreen?: () => void };
type Prefs = { volume: number; muted: boolean; speed: number; captions: boolean };

export const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const PREFS_KEY = "blitzrecorder.player";
const resumeKey = (slug: string) => `blitzrecorder.resume.${slug}`;

function readStored<T>(key: string): T | null {
  try { const raw = localStorage.getItem(key); return raw ? JSON.parse(raw) as T : null; } catch { return null; }
}
function writeStored({ key, value }: { key: string; value: unknown }) {
  try { if (value === null) localStorage.removeItem(key); else localStorage.setItem(key, JSON.stringify(value)); } catch {}
}

export function usePlayback({ slug, source, duration, details }: { slug: string; source: string; duration: number; details: VideoDetails }) {
  const video = useRef<HTMLVideoElement>(null);
  const frame = useRef<HTMLDivElement>(null);
  const hls = useRef<Hls | null>(null);
  const resumeAt = useRef(0);
  const [attempt, setAttempt] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [quality, setQuality] = useState(-1);
  const [levels, setLevels] = useState<{ index: number; label: string }[]>([]);
  const [captions, setCaptions] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [pip, setPip] = useState(false);
  const [canPip, setCanPip] = useState(false);
  const [resume, setResume] = useState<number | null>(null);
  const [state, setState] = useState<MediaState>({ playing: false, ready: false, waiting: false,
    time: 0, duration, buffered: 0, volume: 1, muted: false, speed: 1, ended: false });

  useEffect(() => {
    const element = video.current;
    if (!element) return;
    let disposed = false;
    const linkedStart = Number(new URL(location.href).searchParams.get("t"));
    let requestedStart = resumeAt.current || linkedStart;
    const prefs = readStored<Prefs>(PREFS_KEY);
    if (prefs) {
      if (Number.isFinite(prefs.volume)) element.volume = Math.min(1, Math.max(0, prefs.volume));
      element.muted = Boolean(prefs.muted);
      if (SPEEDS.includes(prefs.speed)) element.defaultPlaybackRate = element.playbackRate = prefs.speed;
    }
    const offerResume = !requestedStart;
    let savedAt = 0;
    resumeAt.current = 0;
    if (!Number.isFinite(requestedStart) || requestedStart < 0) requestedStart = 0;
    const sync = () => {
      const validDuration = Number.isFinite(element.duration) && element.duration > 0 ? element.duration : duration;
      let buffered = 0;
      for (let i = 0; i < element.buffered.length; i++) {
        if (element.buffered.start(i) <= element.currentTime && element.buffered.end(i) >= element.currentTime) buffered = element.buffered.end(i);
      }
      setState({ playing: !element.paused && !element.ended, ready: element.readyState >= 1,
        waiting: !element.paused && element.readyState < 3, time: element.currentTime, duration: validDuration,
        buffered, volume: element.volume, muted: element.muted, speed: element.playbackRate, ended: element.ended });
    };
    const loaded = () => {
      if (prefs) setCaptions(Boolean(prefs.captions));
      const saved = readStored<number>(resumeKey(slug));
      const length = Number.isFinite(element.duration) ? element.duration : duration;
      if (offerResume && typeof saved === "number" && saved > 5 && saved < length - 10) setResume(saved);
      if (requestedStart > 0) element.currentTime = Math.min(requestedStart, Math.max(0, element.duration - 0.05));
      requestedStart = 0;
      setCanPip(Boolean(document.pictureInPictureEnabled && element.requestPictureInPicture));
      sync();
    };
    const remember = () => {
      if (element.ended) { writeStored({ key: resumeKey(slug), value: null }); return; }
      if (Math.abs(element.currentTime - savedAt) < 4 && !element.paused) return;
      savedAt = element.currentTime;
      writeStored({ key: resumeKey(slug), value: element.currentTime > 5 ? Math.floor(element.currentTime) : null });
    };
    const keepPrefs = () => {
      const current = readStored<Prefs>(PREFS_KEY);
      writeStored({ key: PREFS_KEY, value: { captions: current?.captions ?? false, volume: element.volume, muted: element.muted, speed: element.playbackRate } });
    };
    const started = () => setResume(null);
    const failed = () => {
      if (disposed) return;
      setError(navigator.onLine
        ? "This video couldn’t load. Try again in a moment. If it keeps failing, ask the sender for a fresh link."
        : "You’re offline. Playback will resume when you reconnect.");
    };
    let recoveries = 0;
    const events = ["timeupdate", "play", "pause", "ended", "progress", "volumechange", "ratechange", "waiting", "playing", "canplay", "seeked", "seeking"];
    events.forEach((event) => element.addEventListener(event, sync));
    element.addEventListener("loadedmetadata", loaded);
    element.addEventListener("error", failed);
    ["timeupdate", "pause", "ended"].forEach((event) => element.addEventListener(event, remember));
    ["volumechange", "ratechange"].forEach((event) => element.addEventListener(event, keepPrefs));
    ["play", "seeking"].forEach((event) => element.addEventListener(event, started));
    const fullscreenChanged = () => setFullscreen(document.fullscreenElement === frame.current);
    const pipChanged = () => setPip(document.pictureInPictureElement === element);
    document.addEventListener("fullscreenchange", fullscreenChanged);
    element.addEventListener("enterpictureinpicture", pipChanged);
    element.addEventListener("leavepictureinpicture", pipChanged);
    if (!source.endsWith(".m3u8")) element.src = source;
    else void import("hls.js").then(({ default: Hls }) => {
      if (disposed) return;
      if (!Hls.isSupported()) {
        if (element.canPlayType("application/vnd.apple.mpegurl")) element.src = source;
        else failed();
        return;
      }
      const engine = new Hls({ capLevelToPlayerSize: true, maxBufferLength: 30, startLevel: -1 });
      hls.current = engine;
      engine.on(Hls.Events.MANIFEST_PARSED, () => setLevels(engine.levels.map((level, index) => ({ index, label: `${Math.min(level.height, level.width)}p` }))));
      engine.on(Hls.Events.ERROR, (_, data) => {
        if (!data.fatal) return;
        if (recoveries < 3 && navigator.onLine && data.type === Hls.ErrorTypes.NETWORK_ERROR) { recoveries++; engine.startLoad(); return; }
        if (recoveries < 3 && data.type === Hls.ErrorTypes.MEDIA_ERROR) { recoveries++; engine.recoverMediaError(); return; }
        failed();
      });
      engine.on(Hls.Events.FRAG_LOADED, () => { recoveries = 0; });
      engine.loadSource(source);
      engine.attachMedia(element);
    }).catch(failed);
    return () => {
      disposed = true;
      events.forEach((event) => element.removeEventListener(event, sync));
      element.removeEventListener("loadedmetadata", loaded);
      element.removeEventListener("error", failed);
      ["timeupdate", "pause", "ended"].forEach((event) => element.removeEventListener(event, remember));
      ["volumechange", "ratechange"].forEach((event) => element.removeEventListener(event, keepPrefs));
      ["play", "seeking"].forEach((event) => element.removeEventListener(event, started));
      document.removeEventListener("fullscreenchange", fullscreenChanged);
      element.removeEventListener("enterpictureinpicture", pipChanged);
      element.removeEventListener("leavepictureinpicture", pipChanged);
      hls.current?.destroy();
      hls.current = null;
      element.removeAttribute("src");
      element.load();
    };
  }, [slug, source, duration, attempt]);

  useEffect(() => {
    const element = video.current;
    if (!element || !details.transcript.length) return;
    const url = URL.createObjectURL(new Blob([transcriptVTT(details.transcript)], { type: "text/vtt" }));
    const track = document.createElement("track");
    track.kind = "captions";
    track.label = "Transcript";
    track.srclang = details.language ?? "und";
    track.src = url;
    element.append(track);
    track.track.mode = captions ? "showing" : "hidden";
    return () => { track.remove(); URL.revokeObjectURL(url); };
  }, [details.transcript, details.language, captions]);

  const seek = useCallback(({ time }: { time: number }) => {
    const element = video.current;
    if (!element || !Number.isFinite(time) || element.readyState < 1) return;
    element.currentTime = Math.max(0, Math.min(time, Number.isFinite(element.duration) ? element.duration : duration));
  }, [duration]);
  const toggle = useCallback(async () => {
    const element = video.current;
    if (!element) return;
    if (element.paused || element.ended) {
      try { await element.play(); setNotice(null); }
      catch { setNotice("Playback was interrupted. Press play to try again."); }
    } else element.pause();
  }, []);
  const changeSpeed = ({ speed }: { speed: number }) => { if (video.current) video.current.playbackRate = speed; };
  const changeVolume = ({ volume }: { volume: number }) => {
    if (video.current) { video.current.volume = volume; video.current.muted = volume === 0; }
  };
  const toggleMute = () => { if (video.current) video.current.muted = !video.current.muted; };
  const changeQuality = ({ index }: { index: number }) => {
    if (!hls.current || (index !== -1 && !levels.some((level) => level.index === index))) return;
    hls.current.capLevelToPlayerSize = index === -1;
    hls.current.nextLevel = index;
    setQuality(index);
  };
  const toggleFullscreen = async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else if (frame.current?.requestFullscreen) await frame.current.requestFullscreen();
      else (video.current as WebkitVideo | null)?.webkitEnterFullscreen?.();
    } catch { setNotice("Fullscreen is unavailable in this browser."); }
  };
  const togglePip = async () => {
    try {
      if (document.pictureInPictureElement) await document.exitPictureInPicture();
      else await video.current?.requestPictureInPicture();
    } catch { setNotice("Picture in picture is unavailable right now."); }
  };
  const retry = () => {
    resumeAt.current = video.current?.currentTime ?? 0;
    setError(null); setNotice(null); setQuality(-1); setLevels([]);
    setState((current) => ({ ...current, ready: false, playing: false, waiting: true }));
    setAttempt((current) => current + 1);
  };
  const retryWhenOnline = useEffectEvent(retry);
  useEffect(() => {
    if (!error) return;
    const online = () => retryWhenOnline();
    window.addEventListener("online", online);
    return () => window.removeEventListener("online", online);
  }, [error]);
  const toggleCaptions = () => setCaptions((current) => {
    const prefs = readStored<Prefs>(PREFS_KEY);
    const element = video.current;
    writeStored({ key: PREFS_KEY, value: { volume: element?.volume ?? 1, muted: element?.muted ?? false,
      speed: element?.playbackRate ?? 1, ...prefs, captions: !current } });
    return !current;
  });
  const resumePlayback = async () => {
    if (resume === null) return;
    seek({ time: resume });
    setResume(null);
    await toggle();
  };
  return { videoRef: video, frameRef: frame, state, error, notice, levels, quality, captions, fullscreen, pip, canPip, resume,
    seek, toggle, changeSpeed, changeVolume, toggleMute, changeQuality, toggleFullscreen, togglePip,
    toggleCaptions, resumePlayback, retry };
}

export type Playback = Omit<ReturnType<typeof usePlayback>, "videoRef" | "frameRef">;

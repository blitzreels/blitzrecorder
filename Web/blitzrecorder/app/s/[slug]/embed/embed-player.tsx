"use client";

import { useEffect, useRef } from "react";
import type Hls from "hls.js";
import styles from "./embed.module.css";

export function EmbedPlayer({ source, poster, title }: { source: string; poster: string | null; title: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const element = videoRef.current;
    if (!element) return;
    if (!source.endsWith(".m3u8")) { element.src = source; return; }
    let disposed = false;
    let engine: Hls | null = null;
    void import("hls.js").then(({ default: HlsEngine }) => {
      if (disposed) return;
      if (!HlsEngine.isSupported()) { element.src = source; return; }
      engine = new HlsEngine({ capLevelToPlayerSize: true, maxBufferLength: 30 });
      engine.loadSource(source);
      engine.attachMedia(element);
    });
    return () => { disposed = true; engine?.destroy(); };
  }, [source]);

  return <video ref={videoRef} className={styles.video} controls playsInline preload="metadata"
    poster={poster ?? undefined} aria-label={title} />;
}

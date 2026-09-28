"use client";

import { useEffect, useRef, useState } from "react";
import { Captions, Maximize, Minimize, Pause, PictureInPicture2, Play, RotateCcw, RotateCw, Settings2, Volume2, VolumeX } from "lucide-react";
import { Button } from "@/components/ui/button";
import { activeChapter, formatTime, type VideoChapter } from "@/lib/hosting/details";
import type { Playback } from "./use-playback";
import styles from "./player.module.css";

export function PlayerControls({ playback, chapters, hasTranscript }: {
  playback: Playback; chapters: VideoChapter[]; hasTranscript: boolean;
}) {
  const { state } = playback;
  const [settings, setSettings] = useState(false);
  const [hover, setHover] = useState<number | null>(null);
  const panel = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const [draft, setDraft] = useState<number | null>(null);
  const currentTime = draft ?? state.time;
  const percent = Math.min(100, currentTime / Math.max(state.duration, 0.01) * 100);
  const chapter = activeChapter({ chapters, time: hover ?? currentTime });
  useEffect(() => {
    if (!settings) return;
    const dismiss = (event: PointerEvent) => {
      if (!panel.current?.contains(event.target as Node) && !trigger.current?.contains(event.target as Node)) setSettings(false);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); setSettings(false); trigger.current?.focus(); }
    };
    document.addEventListener("pointerdown", dismiss);
    document.addEventListener("keydown", escape);
    panel.current?.querySelector<HTMLButtonElement>("button")?.focus();
    return () => { document.removeEventListener("pointerdown", dismiss); document.removeEventListener("keydown", escape); };
  }, [settings]);
  return <div className={styles.controls}>
    <div className={styles.seekArea} onPointerMove={(event) => {
      const rect = event.currentTarget.getBoundingClientRect();
      setHover(Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)) * state.duration);
    }} onPointerLeave={() => setHover(null)}>
      <div className={styles.seekRail} aria-hidden="true">
        <div className={styles.buffered} style={{ width: `${state.buffered / Math.max(state.duration, 0.01) * 100}%` }} />
        <div className={styles.progress} style={{ width: `${percent}%` }} />
        {chapters.filter((item) => item.start > 0).map((item) => <span key={item.start} className={styles.chapterMark} style={{ left: `${item.start / state.duration * 100}%` }} />)}
        <span className={styles.thumb} style={{ left: `${percent}%` }} />
      </div>
      <input className={styles.seekInput} type="range" aria-label="Seek video" min={0} max={state.duration} step={0.1}
        disabled={!state.ready} value={currentTime} aria-valuetext={`${formatTime(currentTime)} of ${formatTime(state.duration)}`}
        onChange={(event) => { const time = Number(event.target.value); setDraft(time); playback.seek({ time }); }}
        onPointerUp={() => setDraft(null)} onPointerCancel={() => setDraft(null)} onKeyUp={() => setDraft(null)} onBlur={() => setDraft(null)} />
      {hover !== null && <div className={styles.seekPreview} style={{ left: `${Math.max(9, Math.min(91, hover / state.duration * 100))}%` }}>
        {chapter >= 0 && <span>{chapters[chapter].title}</span>}<time>{formatTime(hover)}</time>
      </div>}
    </div>
    <div className={styles.controlRow}>
      <Button variant="ghost" size="icon-lg" aria-label={state.playing ? "Pause" : "Play"} title="Play / pause (Space)"
        disabled={!state.ready} onClick={() => void playback.toggle()}>
        {state.playing ? <Pause fill="currentColor" /> : <Play fill="currentColor" />}
      </Button>
      <Button variant="ghost" size="icon-lg" className={styles.skip} aria-label="Back 10 seconds" title="Back 10 seconds (J)"
        disabled={!state.ready} onClick={() => playback.seek({ time: state.time - 10 })}><RotateCcw /><span>10</span></Button>
      <Button variant="ghost" size="icon-lg" className={styles.skip} aria-label="Forward 10 seconds" title="Forward 10 seconds (L)"
        disabled={!state.ready} onClick={() => playback.seek({ time: state.time + 10 })}><RotateCw /><span>10</span></Button>
      <time className={styles.clock}>{formatTime(currentTime)} <span>/ {formatTime(state.duration)}</span></time>
      <div className={styles.volume}>
        <Button variant="ghost" size="icon-lg" aria-label={state.muted ? "Unmute" : "Mute"} title="Mute (M)" onClick={playback.toggleMute}>
          {state.muted || state.volume === 0 ? <VolumeX /> : <Volume2 />}
        </Button>
        <input type="range" aria-label="Volume" min={0} max={1} step={0.05} value={state.muted ? 0 : state.volume}
          onChange={(event) => playback.changeVolume({ volume: Number(event.target.value) })} />
      </div>
      <div className={styles.rightControls}>
        {hasTranscript && <Button variant="ghost" size="icon-lg" aria-label="Captions" aria-pressed={playback.captions}
          title="Captions (C)" onClick={playback.toggleCaptions}><Captions /></Button>}
        <div className={styles.settingsAnchor}>
          <Button ref={trigger} variant="ghost" size="lg" aria-label="Playback settings" aria-expanded={settings}
            aria-controls="playback-settings" onClick={() => setSettings(!settings)} className={styles.settingsTrigger}>
            <span>{state.speed}×</span><Settings2 />
          </Button>
          {settings && <div ref={panel} id="playback-settings" role="group" aria-label="Playback settings" className={styles.settingsPanel}>
            <span className={styles.settingLabel}>Playback speed</span>
            <div className={styles.choices}>
              {[0.75, 1, 1.25, 1.5, 2].map((speed) => <Button key={speed} variant="ghost" size="sm" aria-pressed={state.speed === speed}
                onClick={() => playback.changeSpeed({ speed })}>{speed}×</Button>)}
            </div>
            <span className={styles.settingLabel}>Quality</span>
            {playback.levels.length ? <div className={styles.choices}>
              {[{ index: -1, label: "Auto" }, ...playback.levels].map((level) => <Button key={level.index} variant="ghost" size="sm"
                aria-pressed={playback.quality === level.index} onClick={() => playback.changeQuality({ index: level.index })}>{level.label}</Button>)}
            </div> : <p className={styles.autoQuality}>Automatically adjusted by your browser</p>}
          </div>}
        </div>
        {playback.canPip && <Button variant="ghost" size="icon-lg" className={styles.pip} aria-label="Picture in picture"
          aria-pressed={playback.pip} title="Picture in picture" onClick={() => void playback.togglePip()}><PictureInPicture2 /></Button>}
        <Button variant="ghost" size="icon-lg" aria-label={playback.fullscreen ? "Exit fullscreen" : "Fullscreen"}
          title="Fullscreen (F)" onClick={() => void playback.toggleFullscreen()}>{playback.fullscreen ? <Minimize /> : <Maximize />}</Button>
      </div>
    </div>
  </div>;
}

"use client";

import { useEffect, useEffectEvent, useRef, useState, type ReactNode } from "react";
import {
  Captions, Check, ChevronDown, ChevronRight, Maximize, Minimize, Pause, PictureInPicture2, Play, RotateCcw, RotateCw,
  Keyboard, Volume1, Volume2, VolumeX,
} from "lucide-react";
import { activeChapter, formatTime, type VideoChapter } from "@/lib/hosting/details";
import type { Playback } from "./use-playback";
import styles from "./player.module.css";

type MenuKey = "speed" | "quality";

function ControlMenu({ id, label, open, onOpenChange, trigger, children }: {
  id: string; label: string; open: boolean; onOpenChange: (open: boolean) => void; trigger: ReactNode; children: ReactNode;
}) {
  const anchor = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const close = useEffectEvent(() => onOpenChange(false));
  useEffect(() => {
    if (!open) return;
    const dismiss = (event: PointerEvent) => { if (!anchor.current?.contains(event.target as Node)) close(); };
    const keys = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close(); button.current?.focus(); return; }
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      const items = [...(anchor.current?.querySelectorAll<HTMLButtonElement>("[role=menuitemradio]") ?? [])];
      const at = items.indexOf(document.activeElement as HTMLButtonElement);
      event.preventDefault();
      items[(at + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length]?.focus();
    };
    document.addEventListener("pointerdown", dismiss);
    document.addEventListener("keydown", keys, true);
    (anchor.current?.querySelector<HTMLButtonElement>("[aria-checked=true]") ?? anchor.current?.querySelector<HTMLButtonElement>("[role=menuitemradio]"))?.focus();
    return () => { document.removeEventListener("pointerdown", dismiss); document.removeEventListener("keydown", keys, true); };
  }, [open]);
  return <div ref={anchor} className={styles.menuAnchor}>
    <button ref={button} type="button" className={styles.menuTrigger} aria-label={label} aria-haspopup="menu"
      aria-expanded={open} aria-controls={id} onClick={() => onOpenChange(!open)}>{trigger}<ChevronDown /></button>
    {open && <div id={id} role="menu" aria-label={label} className={styles.menu}>{children}</div>}
  </div>;
}

function MenuItem({ checked, onSelect, children }: { checked: boolean; onSelect: () => void; children: ReactNode }) {
  return <button type="button" role="menuitemradio" aria-checked={checked} className={styles.menuItem} onClick={onSelect}>
    <span>{children}</span>{checked && <Check />}
  </button>;
}

export function PlayerControls({ playback, speeds, chapters, hasTranscript, onShowChapters, onShowShortcuts }: {
  playback: Playback; speeds: number[]; chapters: VideoChapter[]; hasTranscript: boolean;
  onShowChapters: () => void; onShowShortcuts: () => void;
}) {
  const { state } = playback;
  const [menu, setMenu] = useState<MenuKey | null>(null);
  const [hover, setHover] = useState<number | null>(null);
  const [draft, setDraft] = useState<number | null>(null);
  const safeDuration = Math.max(state.duration, 0.01);
  const currentTime = draft ?? state.time;
  const percent = Math.min(100, currentTime / safeDuration * 100);
  const chapterIndex = activeChapter({ chapters, time: currentTime });
  const hoverChapter = hover === null ? -1 : activeChapter({ chapters, time: hover });
  const volume = state.muted ? 0 : state.volume;
  const VolumeIcon = volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;
  const qualityLabel = playback.quality === -1 ? "Auto" : playback.levels.find((level) => level.index === playback.quality)?.label ?? "Auto";
  const openMenu = (key: MenuKey) => (open: boolean) => setMenu(open ? key : null);

  return <div className={styles.controls}>
    <div className={styles.seekArea} onPointerMove={(event) => {
      const rect = event.currentTarget.getBoundingClientRect();
      setHover(Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)) * state.duration);
    }} onPointerLeave={() => setHover(null)}>
      <div className={styles.seekRail} aria-hidden="true">
        <div className={styles.buffered} style={{ width: `${Math.min(100, state.buffered / safeDuration * 100)}%` }} />
        {hover !== null && <div className={styles.hoverFill} style={{ width: `${hover / safeDuration * 100}%` }} />}
        <div className={styles.progress} style={{ width: `${percent}%` }} />
        {chapters.filter((item) => item.start > 0).map((item) =>
          <span key={item.start} className={styles.chapterGap} style={{ left: `${item.start / safeDuration * 100}%` }} />)}
      </div>
      <span className={styles.thumb} style={{ left: `${percent}%` }} aria-hidden="true" />
      <input className={styles.seekInput} type="range" aria-label="Seek video" min={0} max={state.duration} step={0.1}
        disabled={!state.ready} value={currentTime} aria-valuetext={`${formatTime(currentTime)} of ${formatTime(state.duration)}`}
        onChange={(event) => { const time = Number(event.target.value); setDraft(time); playback.seek({ time }); }}
        onPointerUp={() => setDraft(null)} onPointerCancel={() => setDraft(null)} onKeyUp={() => setDraft(null)} onBlur={() => setDraft(null)} />
      {hover !== null && <div className={styles.seekPreview} style={{ left: `clamp(60px, ${hover / safeDuration * 100}%, calc(100% - 60px))` }}>
        {hoverChapter >= 0 && <span>{chapters[hoverChapter].title}</span>}<time>{formatTime(hover)}</time>
      </div>}
    </div>

    <div className={styles.controlRow}>
      <div className={styles.transport}>
        <button type="button" className={styles.iconButton} aria-label="Back 10 seconds" title="Back 10 seconds (J)"
          disabled={!state.ready} onClick={() => playback.seek({ time: state.time - 10 })}><RotateCcw /></button>
        <button type="button" className={styles.playButton} aria-label={state.playing ? "Pause" : "Play"}
          title={state.playing ? "Pause (Space)" : "Play (Space)"} disabled={!state.ready} onClick={() => void playback.toggle()}>
          {state.playing ? <Pause fill="currentColor" /> : <Play fill="currentColor" />}
        </button>
        <button type="button" className={styles.iconButton} aria-label="Forward 10 seconds" title="Forward 10 seconds (L)"
          disabled={!state.ready} onClick={() => playback.seek({ time: state.time + 10 })}><RotateCw /></button>
      </div>

      <div className={styles.volume}>
        <button type="button" className={styles.iconButton} aria-label={state.muted ? "Unmute" : "Mute"} title="Mute (M)"
          onClick={playback.toggleMute}><VolumeIcon /></button>
        <div className={styles.volumeSlider}>
          <div className={styles.volumeRail} aria-hidden="true"><div style={{ width: `${volume * 100}%` }} /></div>
          <input type="range" aria-label="Volume" min={0} max={1} step={0.05} value={volume}
            onChange={(event) => playback.changeVolume({ volume: Number(event.target.value) })} />
        </div>
      </div>

      <time className={styles.clock} aria-hidden="true">
        {formatTime(currentTime)}<span> / {formatTime(state.duration)}</span>
      </time>

      {chapterIndex >= 0 && <button type="button" className={styles.chapterChip} onClick={onShowChapters}
        title="Show all chapters" aria-label={`Chapter ${chapterIndex + 1}: ${chapters[chapterIndex].title}. Show all chapters`}>
        <span>{chapters[chapterIndex].title}</span><ChevronRight />
      </button>}

      <div className={styles.rightControls}>
        {hasTranscript && <button type="button" className={styles.iconButton} aria-label="Captions" aria-pressed={playback.captions}
          title="Captions (C)" onClick={playback.toggleCaptions}><Captions /></button>}
        <ControlMenu id="playback-speed" label="Playback speed" open={menu === "speed"} onOpenChange={openMenu("speed")}
          trigger={<span className="tabular-nums">{state.speed}×</span>}>
          {speeds.map((speed) => <MenuItem key={speed} checked={state.speed === speed}
            onSelect={() => { playback.changeSpeed({ speed }); setMenu(null); }}>{speed === 1 ? "Normal" : `${speed}×`}</MenuItem>)}
        </ControlMenu>
        {playback.levels.length > 1 && <ControlMenu id="playback-quality" label="Quality" open={menu === "quality"}
          onOpenChange={openMenu("quality")} trigger={<span>{qualityLabel}</span>}>
          {[{ index: -1, label: "Auto" }, ...[...playback.levels].reverse()].map((level) => <MenuItem key={level.index}
            checked={playback.quality === level.index}
            onSelect={() => { playback.changeQuality({ index: level.index }); setMenu(null); }}>{level.label}</MenuItem>)}
        </ControlMenu>}
        <button type="button" className={`${styles.iconButton} ${styles.shortcutsButton}`} aria-label="Keyboard shortcuts"
          title="Keyboard shortcuts (?)" onClick={onShowShortcuts}><Keyboard /></button>
        {playback.canPip && <button type="button" className={`${styles.iconButton} ${styles.pip}`} aria-label="Picture in picture"
          aria-pressed={playback.pip} title="Picture in picture" onClick={() => void playback.togglePip()}><PictureInPicture2 /></button>}
        <button type="button" className={styles.iconButton} aria-label={playback.fullscreen ? "Exit fullscreen" : "Fullscreen"}
          title="Fullscreen (F)" onClick={() => void playback.toggleFullscreen()}>{playback.fullscreen ? <Minimize /> : <Maximize />}</button>
      </div>
    </div>
  </div>;
}

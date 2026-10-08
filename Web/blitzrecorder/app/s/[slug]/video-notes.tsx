"use client";

import { memo, useCallback, useDeferredValue, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { Menu } from "@base-ui/react/menu";
import { ArrowDown, Check, Copy, Download, Ellipsis, Search, X } from "lucide-react";
import { activeChapter, formatTime, transcriptSRT, transcriptText, type TranscriptCue, type VideoDetails } from "@/lib/hosting/details";
import type { TranscriptBrief } from "@/lib/hosting/brief";
import styles from "./player.module.css";

export type NotesTab = "summary" | "transcript" | "chapters";

/** Mirrors the speaker palette in ProjectTranscriptPanel.swift (mint, then system blue, purple, orange, pink, teal). */
const SPEAKER_COLORS = ["var(--primary)", "#0a84ff", "#bf5af2", "#ff9f0a", "#ff375f", "#40c8e0"];

type Block = { speaker: string | null; cues: { cue: TranscriptCue; index: number }[] };

/** Consecutive lines from one speaker read as one paragraph; a paragraph closes after 45 s or a long pause. */
function paragraphs(items: { cue: TranscriptCue; index: number }[]): Block[] {
  const blocks: Block[] = [];
  for (const item of items) {
    const block = blocks.at(-1);
    const last = block?.cues.at(-1);
    if (block && last && block.speaker === item.cue.speaker && item.index === last.index + 1
      && item.cue.start - block.cues[0].cue.start < 45 && item.cue.start - last.cue.end < 3) block.cues.push(item);
    else blocks.push({ speaker: item.cue.speaker, cues: [item] });
  }
  return blocks;
}

function highlight({ text, query }: { text: string; query: string }) {
  const at = query ? text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) : -1;
  return at < 0 ? text : <>{text.slice(0, at)}<mark>{text.slice(at, at + query.length)}</mark>{text.slice(at + query.length)}</>;
}

const Paragraph = memo(function Paragraph({ block, active, color, named, query, onSeek }: {
  block: Block; active: number; color: string | null; named: boolean; query: string; onSeek: (index: number) => void;
}) {
  const first = block.cues[0];
  const current = active >= 0;
  const compact = block.cues.length === 1 && first.cue.text.length <= 24;
  return <div className={styles.paragraph} data-current={current ? "true" : undefined} data-compact={compact ? "true" : undefined}>
    <button type="button" className={styles.paragraphHead} onClick={() => onSeek(first.index)}
      aria-label={`Play from ${formatTime(first.cue.start)}${block.speaker ? `, ${block.speaker}` : ""}`}>
      {named && block.speaker && <span className={styles.avatar} style={{ background: color ?? undefined }} aria-hidden="true">
        {block.speaker.trim().charAt(0).toLocaleUpperCase()}
      </span>}
      {named && block.speaker && <strong>{block.speaker}</strong>}
      <time>{formatTime(first.cue.start)}</time>
    </button>
    <p className={styles.paragraphText} onClick={(event) => {
      if (window.getSelection()?.toString()) return;
      const cue = (event.target as HTMLElement).closest<HTMLElement>("[data-cue]");
      if (cue) onSeek(Number(cue.dataset.cue));
    }}>
      {block.cues.map(({ cue, index }) => <span key={index} data-cue={index} aria-current={index === active ? "true" : undefined}>
        {highlight({ text: cue.text, query })}{" "}
      </span>)}
    </p>
  </div>;
});

function download({ name, text, type }: { name: string; text: string; type: string }) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function fileName(title: string): string {
  return title.normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-").toLowerCase().slice(0, 60) || "transcript";
}

export function VideoNotes({ title, details, brief, time, duration, ready, playing, tab, onTabChange, onSeek }: {
  title: string; details: VideoDetails; brief: TranscriptBrief; time: number; duration: number; ready: boolean; playing: boolean;
  tab: NotesTab; onTabChange: (tab: NotesTab) => void; onSeek: (input: { time: number }) => void;
}) {
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query.trim());
  const [follow, setFollow] = useState(true);
  const [copied, setCopied] = useState(false);
  const list = useRef<HTMLDivElement>(null);
  const { transcript, chapters } = details;

  const speakers = useMemo(() => {
    const names = [...new Set(transcript.map((cue) => cue.speaker).filter((name): name is string => Boolean(name)))];
    return new Map(names.map((name, index) => [name, SPEAKER_COLORS[index % SPEAKER_COLORS.length]]));
  }, [transcript]);
  const active = useMemo(() => {
    let low = 0;
    let high = transcript.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (transcript[middle].start <= time) low = middle + 1;
      else high = middle;
    }
    for (let i = low - 1; i >= 0 && i >= low - 10; i--) if (time < transcript[i].end) return i;
    return -1;
  }, [transcript, time]);
  const chapter = activeChapter({ chapters, time });
  const filtered = useMemo(() => transcript.map((cue, index) => ({ cue, index }))
    .filter(({ cue }) => !deferredQuery || cue.text.toLocaleLowerCase().includes(deferredQuery.toLocaleLowerCase())), [transcript, deferredQuery]);

  const scrollToActive = ({ force }: { force: boolean }) => {
    const container = list.current;
    const item = container?.querySelector<HTMLElement>(`[data-cue="${active}"]`);
    if (!container || !item) return;
    const top = item.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
    if (force || top < container.scrollTop + 8 || top + item.offsetHeight > container.scrollTop + container.clientHeight * 0.7) {
      container.scrollTo({ top: Math.max(0, top - container.clientHeight * 0.3), behavior: playing || force ? "smooth" : "auto" });
    }
  };
  const followActive = useEffectEvent(() => scrollToActive({ force: false }));
  useEffect(() => {
    if (follow && !deferredQuery && tab === "transcript" && active >= 0) followActive();
  }, [active, follow, deferredQuery, tab]);

  const seekCue = useCallback((index: number) => {
    if (!ready) return;
    setFollow(true);
    onSeek({ time: transcript[index].start });
  }, [ready, transcript, onSeek]);
  const copyTranscript = async () => {
    try {
      await navigator.clipboard.writeText(transcriptText(transcript));
      setCopied(true); window.setTimeout(() => setCopied(false), 2000);
    } catch { /* The transcript stays readable and selectable in the panel. */ }
  };
  const blocks = useMemo(() => paragraphs(filtered), [filtered]);
  const sectionIndex = activeChapter({
    chapters: brief.sections.map((section) => ({ start: section.start, title: section.title, summary: null })), time,
  });
  const tabs = ([{ key: "summary", title: "Summary", count: brief.sections.length },
    { key: "transcript", title: "Transcript", count: transcript.length },
    { key: "chapters", title: "Chapters", count: chapters.length }] as const).filter((item) => item.count > 0);

  return <aside id="video-notes" className={styles.notes} aria-label="Summary, transcript, and chapters">
    <div className={styles.notesHeader}>
      {tabs.length > 1 ? <div className={styles.segmented} role="tablist" aria-label="Video content">
        {tabs.map((item) => <button key={item.key} type="button" role="tab" id={`tab-${item.key}`} aria-selected={tab === item.key}
          aria-controls={`panel-${item.key}`} tabIndex={tab === item.key ? 0 : -1} onClick={() => onTabChange(item.key)}
          onKeyDown={(event) => {
            if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
            event.preventDefault();
            const keys = tabs.map((entry) => entry.key);
            const index = keys.indexOf(tab);
            const next = event.key === "Home" ? keys[0] : event.key === "End" ? keys[keys.length - 1]
              : keys[(index + (event.key === "ArrowRight" ? 1 : -1) + keys.length) % keys.length];
            onTabChange(next); document.getElementById(`tab-${next}`)?.focus();
          }}>{item.title}{item.key !== "transcript" && <span>{item.count}</span>}</button>)}
      </div> : <h2 className={styles.notesTitle}>{tabs[0]?.title}</h2>}
      {tab === "transcript" && <Menu.Root>
        <Menu.Trigger className={styles.iconButtonQuiet} aria-label="Transcript options">
          {copied ? <Check /> : <Ellipsis />}
        </Menu.Trigger>
        <Menu.Portal>
          <Menu.Positioner side="bottom" align="end" sideOffset={6} collisionPadding={12} className="z-[60]">
            <Menu.Popup className={styles.notesMenu}>
              <Menu.Item className={styles.notesMenuItem} onClick={() => void copyTranscript()}><Copy />Copy transcript</Menu.Item>
              <Menu.Item className={styles.notesMenuItem}
                onClick={() => download({ name: `${fileName(title)}.txt`, text: transcriptText(transcript), type: "text/plain" })}>
                <Download />Download as text
              </Menu.Item>
              <Menu.Item className={styles.notesMenuItem}
                onClick={() => download({ name: `${fileName(title)}.srt`, text: transcriptSRT(transcript), type: "application/x-subrip" })}>
                <Download />Download subtitles (.srt)
              </Menu.Item>
            </Menu.Popup>
          </Menu.Positioner>
        </Menu.Portal>
      </Menu.Root>}
    </div>

    {tab === "summary" ? <div role="tabpanel" id="panel-summary" aria-labelledby={tabs.length > 1 ? "tab-summary" : undefined}
      aria-label={tabs.length > 1 ? undefined : "Summary"} className={styles.briefList}>
      {brief.sections.map((section) => {
        const current = brief.sections[sectionIndex]?.start === section.start;
        return <div key={section.start} className={styles.briefSection} aria-current={current ? "true" : undefined}>
          <button type="button" className={styles.briefTitle} disabled={!ready} onClick={() => onSeek({ time: section.start })}>
            <strong>{section.title}</strong><time>{formatTime(section.start)}</time>
          </button>
          {section.lines.map((line, index) => <button key={`${line.start}-${index}`} type="button" className={styles.briefLine}
            disabled={!ready} onClick={() => onSeek({ time: line.start })}>
            {line.speaker ? `${line.speaker}: ` : ""}{line.text}
          </button>)}
        </div>;
      })}
    </div> : tab === "transcript" ? <div role="tabpanel" id="panel-transcript" aria-labelledby={tabs.length > 1 ? "tab-transcript" : undefined}
      aria-label={tabs.length > 1 ? undefined : "Transcript"} className={styles.notesBody}>
      <div className={styles.search}>
        <Search />
        <input type="search" aria-label="Search transcript" placeholder="Search transcript" value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Escape" && query) { event.stopPropagation(); setQuery(""); } }} />
        {query && <span className={styles.searchCount} aria-live="polite">{filtered.length}</span>}
        {query && <button type="button" className={styles.clearSearch} aria-label="Clear search" onClick={() => setQuery("")}><X /></button>}
      </div>
      <div className={styles.transcriptWrap}>
        <div ref={list} className={styles.transcriptList} onWheel={() => setFollow(false)} onTouchMove={() => setFollow(false)}>
          {blocks.map((block) => {
            const first = block.cues[0].index;
            const last = block.cues.at(-1)!.index;
            return <Paragraph key={first} block={block} active={active >= first && active <= last ? active : -1}
              color={block.speaker ? speakers.get(block.speaker) ?? null : null} named={speakers.size > 1}
              query={deferredQuery} onSeek={seekCue} />;
          })}
          {!filtered.length && <p className={styles.empty}>No passages match “{query}”.</p>}
        </div>
        {!follow && !deferredQuery && active >= 0 && <button type="button" className={styles.resume}
          onClick={() => { setFollow(true); scrollToActive({ force: true }); }}><ArrowDown />Back to current</button>}
      </div>
    </div> : <div role="tabpanel" id="panel-chapters" aria-labelledby={tabs.length > 1 ? "tab-chapters" : undefined}
      aria-label={tabs.length > 1 ? undefined : "Chapters"} className={styles.chapterList}>
      {chapters.map((item, index) => {
        const end = chapters[index + 1]?.start ?? Math.max(duration, item.start + 1);
        const current = index === chapter;
        return <button key={item.start} type="button" className={styles.chapter} aria-current={current ? "true" : undefined}
          disabled={!ready} onClick={() => onSeek({ time: item.start })}>
          <span className={styles.chapterIndex}>{index + 1}</span>
          <span className={styles.chapterBody}>
            <span className={styles.chapterTitle}><strong>{item.title}</strong><time>{formatTime(item.start)}</time></span>
            {item.summary && <small>{item.summary}</small>}
            {current && <span className={styles.chapterProgress} aria-hidden="true">
              <span style={{ width: `${Math.min(100, (time - item.start) / (end - item.start) * 100)}%` }} />
            </span>}
          </span>
        </button>;
      })}
    </div>}
  </aside>;
}

"use client";

import { memo, useDeferredValue, useEffect, useEffectEvent, useMemo, useRef, useState } from "react";
import { ArrowDown, Check, Copy, Search, X } from "lucide-react";
import { activeChapter, formatTime, type TranscriptCue, type VideoDetails } from "@/lib/hosting/details";
import type { TranscriptBrief } from "@/lib/hosting/brief";
import styles from "./player.module.css";

export type NotesTab = "summary" | "transcript" | "chapters";

/** Mirrors the speaker palette in ProjectTranscriptPanel.swift (mint, then system blue, purple, orange, pink, teal). */
const SPEAKER_COLORS = ["var(--primary)", "#0a84ff", "#bf5af2", "#ff9f0a", "#ff375f", "#40c8e0"];

const CueRow = memo(function CueRow({ cue, index, active, speaker, query, onSeek }: {
  cue: TranscriptCue; index: number; active: boolean; speaker: { name: string; color: string } | null;
  query: string; onSeek: (index: number) => void;
}) {
  const at = query ? cue.text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) : -1;
  return <div className={styles.cueGroup} data-speaker-start={speaker ? "true" : undefined}>
    {speaker && <p className={styles.speaker}><span style={{ background: speaker.color }} />{speaker.name}</p>}
    <button type="button" className={styles.cue} data-cue={index} aria-current={active ? "true" : undefined}
      aria-label={`${formatTime(cue.start)}${cue.speaker ? `, ${cue.speaker}` : ""}: ${cue.text}`} onClick={() => onSeek(index)}>
      <time>{formatTime(cue.start)}</time>
      <span>{at < 0 ? cue.text : <>{cue.text.slice(0, at)}<mark>{cue.text.slice(at, at + query.length)}</mark>{cue.text.slice(at + query.length)}</>}</span>
    </button>
  </div>;
});

export function VideoNotes({ details, brief, time, duration, ready, playing, tab, onTabChange, onSeek }: {
  details: VideoDetails; brief: TranscriptBrief; time: number; duration: number; ready: boolean; playing: boolean;
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

  const seekCue = (index: number) => { if (!ready) return; setFollow(true); onSeek({ time: transcript[index].start }); };
  const copyTranscript = async () => {
    const lines = transcript.map((cue) => `[${formatTime(cue.start)}]${speakers.size > 1 && cue.speaker ? ` ${cue.speaker}:` : ""} ${cue.text}`);
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
      setCopied(true); window.setTimeout(() => setCopied(false), 2000);
    } catch { /* The transcript stays readable and selectable in the panel. */ }
  };
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
      {tab === "transcript" && <button type="button" className={styles.iconButtonQuiet} onClick={() => void copyTranscript()}
        aria-label={copied ? "Transcript copied" : "Copy transcript"} title="Copy transcript with timestamps">
        {copied ? <Check /> : <Copy />}
      </button>}
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
          {filtered.map(({ cue, index }, position) => {
            const previous = filtered[position - 1]?.cue;
            const showSpeaker = speakers.size > 1 && cue.speaker && (!previous || previous.speaker !== cue.speaker);
            return <CueRow key={index} cue={cue} index={index} active={index === active} query={deferredQuery} onSeek={seekCue}
              speaker={showSpeaker && cue.speaker ? { name: cue.speaker, color: speakers.get(cue.speaker)! } : null} />;
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

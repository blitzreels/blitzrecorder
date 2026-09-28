"use client";

import { memo, useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { AlignLeft, ListVideo, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { activeChapter, formatTime, type TranscriptCue, type VideoDetails } from "@/lib/hosting/details";
import styles from "./player.module.css";

const CueRow = memo(function CueRow({ cue, index, active, query, onSeek }: {
  cue: TranscriptCue; index: number; active: boolean; query: string; onSeek: (input: { time: number }) => void;
}) {
  const at = query ? cue.text.toLocaleLowerCase().indexOf(query.toLocaleLowerCase()) : -1;
  return <button type="button" className={styles.cue} data-cue={index} aria-current={active ? "true" : undefined}
    aria-label={`${formatTime(cue.start)}${cue.speaker ? `, ${cue.speaker}` : ""}: ${cue.text}`} onClick={() => onSeek({ time: cue.start })}>
    <time>{formatTime(cue.start)}</time><span>{cue.speaker && <small>{cue.speaker}</small>}
      {at < 0 ? cue.text : <>{cue.text.slice(0, at)}<mark>{cue.text.slice(at, at + query.length)}</mark>{cue.text.slice(at + query.length)}</>}
    </span>
  </button>;
});

export function VideoNotes({ details, time, ready, onSeek }: {
  details: VideoDetails; time: number; ready: boolean; onSeek: (input: { time: number }) => void;
}) {
  const [tab, setTab] = useState(details.transcript.length ? "transcript" : "chapters");
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query.trim());
  const [follow, setFollow] = useState(true);
  const list = useRef<HTMLDivElement>(null);
  const active = useMemo(() => {
    let low = 0;
    let high = details.transcript.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (details.transcript[middle].start <= time) low = middle + 1;
      else high = middle;
    }
    for (let i = low - 1; i >= 0 && i >= low - 10; i--) if (time < details.transcript[i].end) return i;
    return -1;
  }, [details.transcript, time]);
  const chapter = activeChapter({ chapters: details.chapters, time });
  const filtered = useMemo(() => details.transcript.map((cue, index) => ({ cue, index }))
    .filter(({ cue }) => !deferredQuery || cue.text.toLocaleLowerCase().includes(deferredQuery.toLocaleLowerCase())), [details.transcript, deferredQuery]);
  useEffect(() => {
    if (!follow || deferredQuery || tab !== "transcript" || active < 0) return;
    const container = list.current;
    const item = container?.querySelector<HTMLElement>(`[data-cue="${active}"]`);
    if (container && item) {
      const top = item.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
      if (top < container.scrollTop || top + item.offsetHeight > container.scrollTop + container.clientHeight) {
        container.scrollTop = Math.max(0, top - container.clientHeight * 0.3);
      }
    }
  }, [active, follow, deferredQuery, tab]);
  const seek = ({ time }: { time: number }) => { if (ready) onSeek({ time }); };
  return <aside className={styles.notes} aria-label="Video notes">
    <div className={styles.tabs} role="tablist" aria-label="Video content">
      {[{ key: "transcript", title: "Transcript", count: details.transcript.length, icon: AlignLeft },
        { key: "chapters", title: "Chapters", count: details.chapters.length, icon: ListVideo }].filter((item) => item.count > 0).map((item) =>
        <button key={item.key} type="button" role="tab" id={`tab-${item.key}`} aria-selected={tab === item.key}
          aria-controls={`panel-${item.key}`} tabIndex={tab === item.key ? 0 : -1} onClick={() => setTab(item.key)}
          onKeyDown={(event) => {
            if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key) && details.transcript.length && details.chapters.length) {
              event.preventDefault();
              const next = event.key === "Home" ? "transcript" : event.key === "End" ? "chapters" : tab === "transcript" ? "chapters" : "transcript";
              setTab(next); document.getElementById(`tab-${next}`)?.focus();
            }
          }}><item.icon />{item.title}{item.key === "chapters" && <span>{item.count}</span>}</button>)}
    </div>
    {tab === "transcript" ? <div role="tabpanel" id="panel-transcript" aria-labelledby="tab-transcript" className={styles.notesBody}>
      <div className={styles.search}><Search /><input type="search" aria-label="Search transcript" placeholder="Find a word or phrase…" value={query}
        onChange={(event) => setQuery(event.target.value)} />{query && <Button variant="ghost" size="icon-xs" aria-label="Clear search" onClick={() => setQuery("")}><X /></Button>}</div>
      <div className={styles.notesHint}><span aria-live="polite">{query ? `${filtered.length} matching passages` : "Click a passage to jump there"}</span>
        {!query && <button type="button" aria-pressed={follow} onClick={() => setFollow(!follow)}>Follow {follow ? "on" : "off"}</button>}</div>
      <div ref={list} className={styles.transcriptList} onWheel={() => setFollow(false)} onTouchMove={() => setFollow(false)}>
        {filtered.map(({ cue, index }) => <CueRow key={index} cue={cue} index={index} active={index === active} query={deferredQuery} onSeek={onSeek} />)}
        {!filtered.length && <p className={styles.empty}>No passages match “{query}”.</p>}
      </div>
    </div> : <div role="tabpanel" id="panel-chapters" aria-labelledby="tab-chapters" className={styles.chapterList}>
      <p className={styles.chapterHint}>Jump to the part you need.</p>
      {details.chapters.map((item, index) => <button key={item.start} type="button" className={styles.chapter}
        aria-current={index === chapter ? "true" : undefined} disabled={!ready} onClick={() => seek({ time: item.start })}>
        <time>{formatTime(item.start)}</time><span><strong>{item.title}</strong>{item.summary && <small>{item.summary}</small>}</span>
      </button>)}
    </div>}
  </aside>;
}

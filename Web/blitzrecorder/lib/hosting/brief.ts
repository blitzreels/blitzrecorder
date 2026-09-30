import { formatTime, type TranscriptCue, type VideoDetails } from "./details";

export type CallSpeaker = { name: string; seconds: number; percent: number };
export type BriefLine = { start: number; speaker: string | null; text: string };
export type BriefSection = { start: number; title: string; lines: BriefLine[] };
export type TranscriptBrief = {
  /** Long enough that the raw transcript is a poor way to read the call. */
  long: boolean;
  speakers: CallSpeaker[];
  /** Written summary, or a few sentences spread across a long transcript. */
  lead: string | null;
  sections: BriefSection[];
};

const FILLER = /^(?:(?:yeah|yep|yes|ok|okay|right|alright|um+|uh+|hmm+|mhm|mm+|sure|exactly|cool|thanks|thank you|hello|hi|hey|ouais|oui|oké|oke|d'accord|voilà|voila|euh+|hum+|merci|salut|bonjour|exactement|super|allez|c'est ça|c'est ca)[\s,!.?…]*)+$/i;

function clean(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

export function cueScore(text: string): number {
  const value = clean(text);
  if (!value || FILLER.test(value)) return -1;
  let score = Math.min(value.length, 220);
  if (/[.!?…]$/.test(value)) score += 24;
  if (value.length < 32) score -= 36;
  return score;
}

function clip(text: string, max: number): string {
  const value = clean(text);
  if (value.length <= max) return value;
  const cut = value.slice(0, max - 1);
  const space = cut.lastIndexOf(" ");
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

function sentence(text: string): string {
  const value = clean(text);
  return /[.!?…]$/.test(value) ? value : `${value}.`;
}

function byScore(cues: TranscriptCue[]): TranscriptCue[] {
  return [...cues].sort((a, b) => cueScore(b.text) - cueScore(a.text) || a.start - b.start);
}

/** Highest-signal lines, preferring a mix of speakers, in time order. */
function pickLines(cues: TranscriptCue[], count: number): TranscriptCue[] {
  const ranked = byScore(cues);
  const useful = ranked.filter((cue) => cueScore(cue.text) >= 0);
  const source = useful.length ? useful : ranked;
  const picked: TranscriptCue[] = [];
  const seen = new Set<string>();
  for (const cue of source) {
    if (cue.speaker && seen.has(cue.speaker)) continue;
    picked.push(cue);
    if (cue.speaker) seen.add(cue.speaker);
    if (picked.length >= count) break;
  }
  for (const cue of source) {
    if (picked.length >= count) break;
    if (picked.includes(cue)) continue;
    picked.push(cue);
  }
  return picked.sort((a, b) => a.start - b.start);
}

function lineFrom(cue: TranscriptCue): BriefLine {
  return { start: cue.start, speaker: cue.speaker, text: clip(cue.text, 180) };
}

function speakersFrom(transcript: TranscriptCue[]): CallSpeaker[] {
  const seconds = new Map<string, number>();
  for (const cue of transcript) {
    if (!cue.speaker) continue;
    seconds.set(cue.speaker, (seconds.get(cue.speaker) ?? 0) + Math.max(0, cue.end - cue.start));
  }
  const ranked = [...seconds.entries()].filter(([, time]) => time > 0).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const total = ranked.reduce((sum, [, time]) => sum + time, 0);
  if (!ranked.length || total <= 0) return [];
  const exact = ranked.map(([, time]) => time / total * 100);
  const percents = exact.map((value) => Math.floor(value));
  let leftover = 100 - percents.reduce((sum, value) => sum + value, 0);
  const order = exact.map((_, index) => index).sort((a, b) => (exact[b] % 1) - (exact[a] % 1) || exact[b] - exact[a]);
  for (const index of order) {
    if (leftover <= 0) break;
    percents[index] += 1;
    leftover -= 1;
  }
  return ranked.map(([name, time], index) => ({ name, seconds: time, percent: percents[index] }));
}

function chapterSections({ details, duration }: { details: VideoDetails; duration: number }): BriefSection[] | null {
  const chapters = details.chapters;
  if (chapters.length < 2 || chapters.length > 16) return null;
  return chapters.map((chapter, index) => {
    const end = chapters[index + 1]?.start ?? duration;
    const cues = details.transcript.filter((cue) => cue.start >= chapter.start && cue.start < end);
    const lines = chapter.summary
      ? [{ start: chapter.start, speaker: null, text: clip(chapter.summary, 280) }]
      : pickLines(cues, 2).map(lineFrom);
    return { start: chapter.start, title: chapter.title, lines };
  });
}

function timeSections({ transcript, duration }: { transcript: TranscriptCue[]; duration: number }): BriefSection[] {
  if (duration <= 0) return [];
  const count = Math.min(12, Math.max(4, Math.round(duration / 300)));
  const span = duration / count;
  const buckets: TranscriptCue[][] = Array.from({ length: count }, () => []);
  for (const cue of transcript) {
    const index = Math.min(count - 1, Math.max(0, Math.floor(cue.start / span)));
    buckets[index].push(cue);
  }
  const sections: BriefSection[] = [];
  for (const cues of buckets) {
    if (!cues.length) continue;
    const picked = pickLines(cues, 3);
    const titleCue = [...picked].sort((a, b) => cueScore(b.text) - cueScore(a.text) || a.start - b.start)[0];
    if (!titleCue) continue;
    sections.push({
      start: titleCue.start,
      title: clip(clean(titleCue.text).split(/(?<=[.!?…])\s+/)[0] ?? titleCue.text, 96),
      lines: picked.filter((cue) => cue !== titleCue).map(lineFrom),
    });
  }
  const meaningful = sections.filter((section) => cueScore(section.title) >= 0);
  return meaningful.length ? meaningful : sections;
}

function leadFrom({ transcript, duration, summary }: { transcript: TranscriptCue[]; duration: number; summary: string | null }): string | null {
  if (summary) return summary;
  const long = duration >= 8 * 60 || transcript.length >= 48;
  if (!long || duration <= 0) return null;
  const span = duration / 3;
  const picks: TranscriptCue[] = [];
  for (let index = 0; index < 3; index += 1) {
    const start = index * span;
    const end = index === 2 ? duration + 1 : (index + 1) * span;
    const best = pickLines(transcript.filter((cue) => cue.start >= start && cue.start < end), 1)[0];
    if (best && cueScore(best.text) >= 20) picks.push(best);
  }
  if (!picks.length) return null;
  return clip(picks.map((cue) => sentence(cue.text)).join(" "), 520);
}

export function transcriptBrief({ details, duration }: { details: VideoDetails; duration: number }): TranscriptBrief {
  const safeDuration = Number.isFinite(duration) && duration > 0 ? duration : 0;
  const transcript = details.transcript;
  const long = safeDuration >= 8 * 60 || transcript.length >= 48;
  const sections = chapterSections({ details, duration: safeDuration })
    ?? (long ? timeSections({ transcript, duration: safeDuration }) : []);
  return {
    long, speakers: speakersFrom(transcript), sections,
    lead: leadFrom({ transcript, duration: safeDuration, summary: details.summary }),
  };
}

export function languageLabel(code: string | null): string | null {
  if (!code) return null;
  try {
    const name = new Intl.DisplayNames(["en"], { type: "language" }).of(code);
    if (!name || name.toLowerCase() === code.toLowerCase()) return null;
    return name;
  } catch {
    return null;
  }
}

/** Link-preview text: who, how long, when, then the résumé. */
export function shareDescription({ details, duration }: { details: VideoDetails; duration: number }): string {
  const brief = transcriptBrief({ details, duration });
  const who = brief.speakers.slice(0, 4).map((speaker) => speaker.name).join(", ");
  const recorded = details.recordedAt && Number.isFinite(Date.parse(details.recordedAt))
    ? new Intl.DateTimeFormat("en", { dateStyle: "medium", timeZone: "UTC" }).format(new Date(details.recordedAt))
    : null;
  const context = [who, formatTime(duration), recorded].filter(Boolean).join(" · ");
  const text = [context, brief.lead].filter(Boolean).join(" — ");
  return text.slice(0, 300) || "Watch a video shared with BlitzRecorder.";
}

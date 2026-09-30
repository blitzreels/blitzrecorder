export type TranscriptCue = { start: number; end: number; text: string; speaker: string | null };
export type VideoChapter = { start: number; title: string; summary: string | null };
export type VideoDetails = {
  version: 1;
  summary: string | null;
  language: string | null;
  recordedAt: string | null;
  transcript: TranscriptCue[];
  chapters: VideoChapter[];
};

export const EMPTY_DETAILS: VideoDetails = {
  version: 1, summary: null, language: null, recordedAt: null, transcript: [], chapters: [],
};
/** Vercel rejects function request bodies over 4.5 MB. */
export const DETAILS_MAX_BYTES = 4 * 1024 * 1024;

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid video details.");
  return value as Record<string, unknown>;
}

function text({ value, max }: { value: unknown; max: number }): string | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || value.length > max) throw new Error("Video text is too long or invalid.");
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").trim() || null;
}

function time({ value, duration }: { value: unknown; duration: number }): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > duration) {
    throw new Error("Video details must use timestamps from the exported video.");
  }
  return value;
}

export function parseVideoDetails({ value, duration }: { value: unknown; duration: number }): VideoDetails {
  const data = record(value);
  if (data.version !== 1) throw new Error("Unsupported video details version.");
  if (!Array.isArray(data.transcript) || !Array.isArray(data.chapters) || data.chapters.length > 1000) {
    throw new Error("Video details contain too many items or missing lists.");
  }
  const transcript = compactTranscript(data.transcript.map((item): TranscriptCue => {
    const cue = record(item);
    const start = time({ value: cue.start, duration });
    const end = time({ value: cue.end, duration });
    const content = text({ value: cue.text, max: 2000 });
    if (end <= start || !content) throw new Error("Transcript entries need text and a valid time range.");
    return { start, end, text: content, speaker: text({ value: cue.speaker, max: 100 }) };
  }).sort((a, b) => a.start - b.start || a.end - b.end));
  const chapters = data.chapters.map((item): VideoChapter => {
    const chapter = record(item);
    const start = time({ value: chapter.start, duration });
    const title = text({ value: chapter.title, max: 160 });
    if (!title || start >= duration) throw new Error("Chapters need a title and a timestamp within the video.");
    return { start, title, summary: text({ value: chapter.summary, max: 1000 }) };
  }).sort((a, b) => a.start - b.start);
  if (chapters.some((chapter, index) => index > 0 && chapter.start === chapters[index - 1].start)) {
    throw new Error("Chapter timestamps must be distinct.");
  }
  const language = text({ value: data.language, max: 35 });
  if (language && !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(language)) throw new Error("Invalid transcript language.");
  const recordedAt = text({ value: data.recordedAt, max: 40 });
  if (recordedAt && !/^\d{4}-\d{2}-\d{2}T/.test(recordedAt)) throw new Error("Invalid recording date.");
  if (recordedAt && !Number.isFinite(Date.parse(recordedAt))) throw new Error("Invalid recording date.");
  const result: VideoDetails = {
    version: 1, summary: text({ value: data.summary, max: 10000 }), language,
    recordedAt: recordedAt ? new Date(recordedAt).toISOString() : null, transcript, chapters,
  };
  if (new TextEncoder().encode(JSON.stringify(result)).length > DETAILS_MAX_BYTES) throw new Error("Video details are too large.");
  return result;
}

export function joinsCue({ prior, start, end }: { prior: TranscriptCue; start: number; end: number }): boolean {
  return start - prior.end < 0.8 && end - prior.start < 7 && prior.text.length < 180 && !/[.!?…]$/.test(prior.text);
}

export function appendCueText({ prior, text }: { prior: TranscriptCue; text: string }): void {
  prior.text += /^[,.;:!?]/.test(text) ? text : ` ${text}`;
}

/** Joins words into phrases per speaker, so overlapping speech doesn't split every sentence into single words. */
export function compactTranscript(cues: TranscriptCue[]): TranscriptCue[] {
  const result: TranscriptCue[] = [];
  const open = new Map<string | null, TranscriptCue>();
  for (const cue of cues) {
    const prior = open.get(cue.speaker);
    if (prior && joinsCue({ prior, start: cue.start, end: cue.end })) {
      appendCueText({ prior, text: cue.text });
      prior.end = Math.max(prior.end, cue.end);
      continue;
    }
    const next = { ...cue };
    result.push(next);
    open.set(cue.speaker, next);
  }
  return result;
}

export function formatTime(seconds: number): string {
  const total = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const hours = Math.floor(total / 3600);
  return `${hours ? `${hours}:` : ""}${String(Math.floor(total / 60) % 60).padStart(hours ? 2 : 1, "0")}:${String(total % 60).padStart(2, "0")}`;
}

export function activeChapter({ chapters, time }: { chapters: VideoChapter[]; time: number }): number {
  let low = 0;
  let high = chapters.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (chapters[middle].start <= time) low = middle + 1;
    else high = middle;
  }
  return low - 1;
}

export function transcriptVTT(cues: TranscriptCue[]): string {
  const stamp = (seconds: number) => {
    const ms = Math.round(seconds * 1000);
    return `${String(Math.floor(ms / 3600000)).padStart(2, "0")}:${String(Math.floor(ms / 60000) % 60).padStart(2, "0")}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}.${String(ms % 1000).padStart(3, "0")}`;
  };
  const escape = (value: string) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replace(/\s+/g, " ");
  return `WEBVTT\n\n${cues.map((cue, index) => `${index + 1}\n${stamp(cue.start)} --> ${stamp(cue.end)}\n${escape(cue.text)}\n`).join("\n")}`;
}

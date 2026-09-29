import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { EMPTY_DETAILS, appendCueText, joinsCue, parseVideoDetails, type TranscriptCue, type VideoDetails } from "./details";
import type { VideoInspection } from "./transcode";

type LocalWord = { text: string; startTime: number; endTime: number; speakerID?: string };
type LocalTranscript = {
  duration: number; suggestedTitle?: string; words?: LocalWord[];
  speakers: { id: string; name: string }[];
  segments: (LocalWord & { speakerID: string })[];
};
type LocalProject = {
  title: string; createdAt: string;
  timelineEdits?: { cuts?: { start: number; end: number; enabled: boolean }[] };
  chapters?: { time: number; endTime?: number; title: string; summary?: string }[];
};
type Kept = { start: number; end: number; output: number };

export function projectLocalDetails({ transcript, project, playbackRate, outputDuration }: {
  transcript: LocalTranscript; project: LocalProject | null; playbackRate: number; outputDuration: number;
}): VideoDetails {
  if (!Number.isFinite(playbackRate) || playbackRate < 0.5 || playbackRate > 3 || !Number.isFinite(transcript.duration) || transcript.duration <= 0) {
    throw new Error("Provide the export playback speed and a valid local transcript.");
  }
  const removed = (project?.timelineEdits?.cuts ?? []).filter((cut) => cut.enabled)
    .map((cut) => {
      if (!Number.isFinite(cut.start) || !Number.isFinite(cut.end) || cut.end < cut.start) throw new Error("Invalid project cut.");
      return { start: Math.max(0, cut.start), end: Math.min(transcript.duration, cut.end) };
    }).filter((cut) => cut.end > cut.start).sort((a, b) => a.start - b.start);
  const kept: Kept[] = [];
  let cursor = 0;
  let output = 0;
  for (const cut of removed) {
    if (cut.start > cursor) {
      kept.push({ start: cursor, end: cut.start, output });
      output += (cut.start - cursor) / playbackRate;
    }
    cursor = Math.max(cursor, cut.end);
  }
  if (cursor < transcript.duration) {
    kept.push({ start: cursor, end: transcript.duration, output });
    output += (transcript.duration - cursor) / playbackRate;
  }
  if (Math.abs(output - outputDuration) > 0.35) {
    throw new Error("The transcript/project does not match this export. Provide the matching project and export speed, or details already timed to the export.");
  }
  const speakerNames = new Map(transcript.speakers.map((speaker) => [speaker.id, speaker.name || speaker.id]));
  const cues: TranscriptCue[] = [];
  const hasWords = Boolean(transcript.words?.length);
  const units = [...(hasWords ? transcript.words! : transcript.segments)].sort((a, b) => a.startTime - b.startTime);
  const open = new Map<string | null, { cue: TranscriptCue; range: number }>();
  let rangeIndex = 0;
  for (const unit of units) {
    if (!Number.isFinite(unit.startTime) || !Number.isFinite(unit.endTime) || unit.endTime <= unit.startTime || typeof unit.text !== "string") {
      throw new Error("The local transcript contains invalid timestamps or text.");
    }
    while (rangeIndex < kept.length && kept[rangeIndex].end <= unit.startTime) rangeIndex++;
    const range = kept[rangeIndex];
    if (!range || unit.startTime < range.start || unit.endTime > range.end + 0.001) continue;
    const start = range.output + (unit.startTime - range.start) / playbackRate;
    const end = Math.min(outputDuration, range.output + (unit.endTime - range.start) / playbackRate);
    if (end <= start) continue;
    const speaker = unit.speakerID ? speakerNames.get(unit.speakerID) ?? unit.speakerID : null;
    const prior = open.get(speaker);
    if (hasWords && prior && prior.range === rangeIndex && joinsCue({ prior: prior.cue, start, end })) {
      appendCueText({ prior: prior.cue, text: unit.text.trim() });
      prior.cue.end = end;
      continue;
    }
    const cue = { start, end, text: unit.text.trim(), speaker };
    cues.push(cue);
    open.set(speaker, { cue, range: rangeIndex });
  }
  const orderedChapters = [...(project?.chapters ?? [])].sort((a, b) => a.time - b.time);
  const chapters = orderedChapters.flatMap((chapter, index) => {
    const chapterEnd = chapter.endTime ?? orderedChapters[index + 1]?.time ?? transcript.duration;
    const range = kept.find((part) => part.end > chapter.time && part.start < chapterEnd);
    if (!range) return [];
    const start = range.output + (Math.max(chapter.time, range.start) - range.start) / playbackRate;
    return start < outputDuration ? [{ start, title: chapter.title, summary: chapter.summary ?? null }] : [];
  }).filter((chapter, index, all) => index === 0 || chapter.start !== all[index - 1].start);
  return parseVideoDetails({ duration: outputDuration, value: {
    ...EMPTY_DETAILS, transcript: cues, chapters, recordedAt: project?.createdAt ?? null,
  } });
}

async function readJSON(file: string): Promise<unknown> {
  if ((await stat(file)).size > 16 * 1024 * 1024) throw new Error("Local metadata file is too large.");
  return JSON.parse(await readFile(file, "utf8"));
}

export async function localVideoDetails({ file, info, projectPath, transcriptPath, detailsPath, playbackRate }: {
  file: string; info: VideoInspection; projectPath: string | null; transcriptPath: string | null;
  detailsPath: string | null; playbackRate: number;
}): Promise<{ title: string; details: VideoDetails }> {
  if (detailsPath && (projectPath || transcriptPath)) throw new Error("Use exported details or local project/transcript files, not both.");
  const project = projectPath ? await readJSON(projectPath) as LocalProject : null;
  const transcriptFile = transcriptPath ?? (projectPath ? path.join(path.dirname(projectPath), "transcript.json") : null);
  const transcript = transcriptFile ? await readJSON(transcriptFile) as LocalTranscript : null;
  const imported = detailsPath ? await readJSON(detailsPath) : null;
  const details = imported ? parseVideoDetails({ value: imported, duration: info.duration })
    : transcript ? projectLocalDetails({ transcript, project, playbackRate, outputDuration: info.duration })
      : { ...EMPTY_DETAILS, summary: info.description, recordedAt: info.recordedAt };
  const importedTitle = imported && typeof imported === "object" && "title" in imported ? imported.title : null;
  if (importedTitle !== null && (typeof importedTitle !== "string" || !importedTitle.trim() || importedTitle.length > 160)) {
    throw new Error("The generated title must contain 1–160 characters.");
  }
  const title = project?.title || transcript?.suggestedTitle || importedTitle || info.title || path.basename(file, path.extname(file));
  return { title: title.trim().slice(0, 160), details };
}

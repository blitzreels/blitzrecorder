import test from "node:test";
import assert from "node:assert/strict";
import { EMPTY_DETAILS, parseVideoDetails, transcriptVTT, formatTime, activeChapter } from "../../lib/hosting/details";
import { localVideoDetails, projectLocalDetails } from "../../lib/hosting/local-details";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const words = [
  { text: "Hello", startTime: 0, endTime: 1, speakerID: "one" },
  { text: "again.", startTime: 1, endTime: 2, speakerID: "one" },
  { text: "Wrong take", startTime: 3, endTime: 4, speakerID: "one" },
  { text: "Keep", startTime: 6, endTime: 7, speakerID: "one" },
  { text: "this.", startTime: 7, endTime: 8, speakerID: "one" },
];
const transcript = { duration: 10, speakers: [{ id: "one", name: "Alex" }], words, segments: words };
const project = { title: "Recording", createdAt: "2026-01-01T00:00:00Z",
  timelineEdits: { cuts: [{ start: 2, end: 5, enabled: true }, { start: 4, end: 6, enabled: true }, { start: 7, end: 10, enabled: false }] },
  chapters: [{ time: 0, title: "Intro" }, { time: 2, endTime: 6, title: "Removed take" }, { time: 6, title: "Final take" }] };

test("local transcript and chapters follow merged cuts and export speed without exposing removed takes", () => {
  const output = projectLocalDetails({ transcript, project, playbackRate: 1.5, outputDuration: 4 });
  assert.equal(output.transcript.map((cue) => cue.text).join(" "), "Hello again. Keep this.");
  assert.equal(output.transcript[1].start, 2 / 1.5);
  assert.equal(output.transcript[1].end, 4 / 1.5);
  assert.deepEqual(output.chapters.map(({ title, start }) => [title, start]), [["Intro", 0], ["Final take", 2 / 1.5]]);
  assert.equal(output.transcript[0].speaker, "Alex");
});

test("export speed is applied even when there are no cuts", () => {
  const output = projectLocalDetails({ transcript, project: null, playbackRate: 2, outputDuration: 5 });
  assert.equal(output.transcript.at(-1)?.end, 4);
});

test("mismatched exports fail instead of publishing incorrect timings", () => {
  assert.throws(() => projectLocalDetails({ transcript, project, playbackRate: 1, outputDuration: 10 }), /does not match/);
  assert.throws(() => projectLocalDetails({ transcript, project, playbackRate: NaN, outputDuration: 4 }));
});

test("without word timestamps, partially deleted sentences are omitted instead of leaking deleted text", () => {
  const output = projectLocalDetails({ transcript: { ...transcript, words: undefined, segments: [
    { text: "Private discarded take and retained words", startTime: 1, endTime: 7, speakerID: "one" },
    { text: "Safe sentence.", startTime: 8, endTime: 9, speakerID: "one" },
  ] }, project, playbackRate: 1.5, outputDuration: 4 });
  assert.deepEqual(output.transcript.map((cue) => cue.text), ["Safe sentence."]);
});

test("metadata parsing allowlists public fields and rejects invalid or unbounded input", () => {
  const valid = { ...EMPTY_DETAILS, transcript: [{ start: 0, end: 2, text: "Hello", speaker: null }] };
  assert.deepEqual(parseVideoDetails({ value: { ...valid, mediaPath: "/private", speakers: [{ context: "Private context" }] }, duration: 10 }), valid);
  for (const value of [null, { ...valid, version: 2 }, { ...valid, language: "../../" }, { ...valid, recordedAt: "oops" },
    { ...valid, summary: "a".repeat(10001) }, { ...valid, transcript: [{ start: NaN, end: 2, text: "Hello" }] },
    { ...valid, transcript: [{ start: 0, end: 11, text: "Hello" }] }, { ...valid, chapters: [{ start: 2, title: "A" }, { start: 2, title: "B" }] },
    { ...valid, transcript: Array.from({ length: 6001 }, () => valid.transcript[0]) }]) {
    assert.throws(() => parseVideoDetails({ value, duration: 10 }));
  }
});

test("VTT text cannot inject cues or markup and timestamp rounding remains valid", () => {
  const result = transcriptVTT([{ start: 59.9999, end: 62, text: "<script>\n\n00:00:00.000 --> 00:00:02.000 &", speaker: null }]);
  assert.ok(result.includes("00:01:00.000 --> 00:01:02.000"));
  assert.ok(result.includes("&lt;script&gt; 00:00:00.000 --&gt; 00:00:02.000 &amp;"));
  assert.equal(formatTime(3601), "1:00:01");
  assert.equal(formatTime(NaN), "0:00");
});

test("chapter lookup handles lead-in, exact boundaries and the final chapter", () => {
  const chapters = [{ start: 2, title: "First", summary: null }, { start: 5, title: "Last", summary: null }];
  assert.equal(activeChapter({ chapters, time: 0 }), -1);
  assert.equal(activeChapter({ chapters, time: 2 }), 0);
  assert.equal(activeChapter({ chapters, time: 5 }), 1);
  assert.equal(activeChapter({ chapters: [], time: 5 }), -1);
});

test("the uploader reuses generated title and summary without forwarding arbitrary local metadata", async () => {
  const folder = await mkdtemp(path.join(tmpdir(), "hosting-details-test-"));
  try {
    const detailsPath = path.join(folder, "details.json");
    await writeFile(detailsPath, JSON.stringify({ ...EMPTY_DETAILS, title: "Generated title", summary: "Generated summary", mediaPath: "/private/source" }));
    const info = { duration: 10, width: 1920, height: 1080, hasAudio: true, frameRate: 30, codec: "h264",
      title: "Embedded title", description: "Embedded description", recordedAt: null };
    const result = await localVideoDetails({ file: "/local/export.mp4", info, projectPath: null, transcriptPath: null, detailsPath, playbackRate: 1 });
    assert.equal(result.title, "Generated title");
    assert.equal(result.details.summary, "Generated summary");
    assert.equal("mediaPath" in result.details, false);
    const embedded = await localVideoDetails({ file: "/local/export.mp4", info, projectPath: null, transcriptPath: null, detailsPath: null, playbackRate: 1 });
    assert.equal(embedded.title, "Embedded title");
    assert.equal(embedded.details.summary, "Embedded description");
  } finally { await rm(folder, { recursive: true, force: true }); }
});

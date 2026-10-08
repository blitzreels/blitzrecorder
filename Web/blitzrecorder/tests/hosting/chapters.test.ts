import test from "node:test";
import assert from "node:assert/strict";
import { readableChapters, type VideoChapter } from "../../lib/hosting/details";

const every = ({ seconds, count }: { seconds: number; count: number }): VideoChapter[] =>
  Array.from({ length: count }, (_, index) => ({ start: index * seconds, title: `Part ${index + 1}`, summary: null }));

test("a one-minute video shows no chapters even when the project has eight", () => {
  assert.deepEqual(readableChapters({ chapters: every({ seconds: 7.5, count: 8 }), duration: 60 }), []);
});

test("dense chapters merge down to one every tenth of the video", () => {
  const kept = readableChapters({ chapters: every({ seconds: 20, count: 30 }), duration: 600 });
  assert.deepEqual(kept.map((chapter) => chapter.start), [0, 60, 120, 180, 240, 300, 360, 420, 480, 540]);
});

test("well spaced chapters survive and the first one snaps to the start", () => {
  const chapters = [{ start: 4, title: "Intro", summary: null }, { start: 95, title: "Demo", summary: "How it works" },
    { start: 170, title: "Pricing", summary: null }];
  assert.deepEqual(readableChapters({ chapters, duration: 240 }).map(({ start, title }) => [start, title]),
    [[0, "Intro"], [95, "Demo"], [170, "Pricing"]]);
});

test("a chapter in the last moments is dropped, and one chapter alone is not worth showing", () => {
  const chapters = [{ start: 0, title: "Talk", summary: null }, { start: 290, title: "Bye", summary: null }];
  assert.deepEqual(readableChapters({ chapters, duration: 300 }), []);
});

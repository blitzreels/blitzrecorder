import test from "node:test";
import assert from "node:assert/strict";
import { EMPTY_DETAILS, type TranscriptCue } from "../../lib/hosting/details";
import { cueScore, shareDescription, transcriptBrief } from "../../lib/hosting/brief";

function cue(start: number, text: string, speaker: string | null, seconds = 6): TranscriptCue {
  return { start, end: start + seconds, text, speaker };
}

test("filler and short acknowledgements lose to a real sentence", () => {
  assert.equal(cueScore("yeah"), -1);
  assert.equal(cueScore("ouais ouais"), -1);
  assert.ok(cueScore("We should ship the annual plan on Monday.") > cueScore("ok sure"));
});

test("a thirty-minute call becomes a short résumé instead of every line", () => {
  const transcript: TranscriptCue[] = [];
  for (let minute = 0; minute < 30; minute += 1) {
    const start = minute * 60;
    transcript.push(cue(start, minute % 2 ? "yeah" : "ok", minute % 2 ? "Sam" : "Alex", 1));
    transcript.push(cue(start + 5, `Point ${minute}: we decided item ${minute} is in scope for the launch.`, minute % 2 ? "Sam" : "Alex", 20));
  }
  const brief = transcriptBrief({ details: { ...EMPTY_DETAILS, transcript, language: "en" }, duration: 30 * 60 });
  assert.equal(brief.long, true);
  assert.ok(brief.sections.length >= 6 && brief.sections.length <= 12);
  assert.ok(brief.sections.every((section) => !/^(yeah|ok)$/i.test(section.title)));
  assert.ok(brief.lead?.includes("Point"));
  assert.ok((brief.lead?.length ?? 0) < 600);
  assert.deepEqual(brief.speakers.map((speaker) => speaker.name).sort(), ["Alex", "Sam"]);
  assert.equal(brief.speakers.reduce((sum, speaker) => sum + speaker.percent, 0), 100);
  const description = shareDescription({ details: { ...EMPTY_DETAILS, transcript, recordedAt: "2026-09-12T15:00:00.000Z" }, duration: 30 * 60 });
  assert.match(description, /Alex, Sam/);
  assert.match(description, /Sep 12, 2026|12 Sep 2026/);
  assert.ok(description.length <= 300);
});

test("chapters replace time slices and keep the written summary as the lead", () => {
  const transcript = [
    cue(0, "Welcome, this is the pricing review for the annual plan.", "Alex"),
    cue(70, "The cap should stay at two hundred dollars.", "Sam"),
    cue(140, "Then we close and ship on Friday.", "Alex"),
  ];
  const details = {
    ...EMPTY_DETAILS, summary: "Pricing review. Cap stays, ship Friday.", transcript,
    chapters: [
      { start: 0, title: "Pricing", summary: "Annual plan and the bonus cap." },
      { start: 120, title: "Close", summary: null },
    ],
  };
  const brief = transcriptBrief({ details, duration: 200 });
  assert.equal(brief.lead, "Pricing review. Cap stays, ship Friday.");
  assert.deepEqual(brief.sections.map((section) => section.title), ["Pricing", "Close"]);
  assert.equal(brief.sections[0].lines[0].text, "Annual plan and the bonus cap.");
  assert.match(brief.sections[1].lines.map((line) => line.text).join(" "), /Friday/);
});

test("a short video keeps the transcript and does not invent a résumé", () => {
  const transcript = [cue(0, "Hello again.", "Alex", 2), cue(2, "Keep this.", "Alex", 2)];
  const brief = transcriptBrief({ details: { ...EMPTY_DETAILS, transcript }, duration: 60 });
  assert.equal(brief.long, false);
  assert.equal(brief.lead, null);
  assert.deepEqual(brief.sections, []);
  assert.deepEqual(brief.speakers, [{ name: "Alex", seconds: 4, percent: 100 }]);
});

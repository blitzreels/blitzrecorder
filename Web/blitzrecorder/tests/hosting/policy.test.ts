import test from "node:test";
import assert from "node:assert/strict";
import { parseUploadInput, partSize, PART_BYTES, reservationBytes, safeDeliveryPath, tokenHash, newAccessToken } from "../../lib/hosting/model";
import { encodeArguments, renditions } from "../../lib/hosting/transcode";

const valid = { title: "Demo", bytes: 1024, duration: 12, contentType: "video/mp4", requestKey: "a".repeat(24) };

test("upload metadata rejects unbounded sizes, durations and unsupported files", () => {
  for (const body of [null, {}, { ...valid, bytes: NaN }, { ...valid, bytes: -1 }, { ...valid, bytes: 6 * 1024 ** 3 },
    { ...valid, duration: Infinity }, { ...valid, duration: 3601 }, { ...valid, contentType: "text/html" },
    { ...valid, title: " " }, { ...valid, requestKey: "../a" }]) {
    assert.throws(() => parseUploadInput(body));
  }
  const input = parseUploadInput(valid);
  assert.ok(reservationBytes(input) > input.bytes);
});

test("a playable 1080p upload reserves only its own bytes and rejects anything larger", () => {
  const video = { width: 1920, height: 1080, frameRate: 60 };
  const input = parseUploadInput({ ...valid, video });
  assert.deepEqual(input.video, video);
  assert.equal(reservationBytes(input), valid.bytes + 1024 ** 2);
  assert.deepEqual(parseUploadInput({ ...valid, video: { width: 1080, height: 1920, frameRate: null } }).video,
    { width: 1080, height: 1920, frameRate: null });
  for (const bad of [{ width: 2560, height: 1440 }, { width: 1920, height: 1200 }, { width: 1.5, height: 2 }, null, { ...video, frameRate: 0 }]) {
    assert.throws(() => parseUploadInput({ ...valid, video: { frameRate: null, ...bad } }));
  }
  assert.throws(() => parseUploadInput({ ...valid, contentType: "video/quicktime", video }));
});

test("direct MP4 calls longer than an hour and larger than 5 GB are only bounded by the plan", () => {
  const video = { width: 1920, height: 1080, frameRate: 30 };
  const long = { ...valid, bytes: 20 * 1024 ** 3, duration: 5 * 3600, video };
  assert.equal(parseUploadInput(long).duration, 5 * 3600);
  assert.throws(() => parseUploadInput({ ...long, video: undefined }));
  assert.throws(() => parseUploadInput({ ...long, duration: 24 * 3600 + 1 }));
  assert.throws(() => parseUploadInput({ ...long, bytes: 10_001 * PART_BYTES }));
});

test("part sizes bind each signed URL to the expected file bounds", () => {
  assert.equal(partSize({ bytes: PART_BYTES * 2 + 17, number: 1 }), PART_BYTES);
  assert.equal(partSize({ bytes: PART_BYTES * 2 + 17, number: 3 }), 17);
  for (const number of [0, -1, 4, 1.5, NaN, Infinity]) assert.throws(() => partSize({ bytes: PART_BYTES * 2 + 17, number }));
});

test("only generated playback files can be delivered, never source or traversal paths", () => {
  for (const path of ["video.mp4", "master.m3u8", "poster.jpg", "v1080/init.mp4", "v720/segment-000012.m4s"]) assert.equal(safeDeliveryPath(path), true);
  for (const path of ["source", "../../source", "v720/../source", "v720/%2e%2e/source", "secret.json", "v720/segment-x.m4s"]) {
    assert.equal(safeDeliveryPath(path), false);
  }
});

test("renditions preserve portrait and landscape geometry without upscaling", () => {
  const landscape = renditions({ duration: 10, width: 1920, height: 1080, hasAudio: true });
  assert.deepEqual(landscape.map(({ width, height }) => [width, height]), [[852, 480], [1280, 720], [1920, 1080]]);
  const portrait = renditions({ duration: 10, width: 1080, height: 1920, hasAudio: false });
  assert.deepEqual(portrait.map(({ width, height }) => [width, height]), [[480, 852], [720, 1280], [1080, 1920]]);
  assert.deepEqual(renditions({ duration: 10, width: 400, height: 300, hasAudio: false }).map(({ width, height }) => [width, height]), [[400, 300]]);
});

test("one ffmpeg pass decodes the source once and writes every rendition", () => {
  const ladder = renditions({ duration: 10, width: 1920, height: 1080, hasAudio: true });
  const args = encodeArguments({ source: "/work/source.mov", destination: "/work/stream", ladder });
  assert.equal(args.filter((arg) => arg === "-i").length, 1);
  assert.match(args[args.indexOf("-filter_complex") + 1], /^\[0:v\]split=3\[s0\]\[s1\]\[s2\];/);
  assert.deepEqual(args.filter((arg) => arg.endsWith("index.m3u8")),
    ["/work/stream/v480/index.m3u8", "/work/stream/v720/index.m3u8", "/work/stream/v1080/index.m3u8"]);
  assert.equal(args[args.indexOf("-progress") + 1], "pipe:1");
});

test("owner keys are random bearer credentials and only their digests are stored", () => {
  const first = newAccessToken();
  assert.match(first, /^brh_[A-Za-z0-9_-]{43}$/);
  assert.notEqual(first, newAccessToken());
  assert.match(tokenHash(first), /^[a-f0-9]{64}$/);
  assert.notEqual(tokenHash(first), tokenHash(newAccessToken()));
});

test("streaming byte ranges support seeking and reject invalid or multi-range requests", async () => {
  const modulePath = new URL("../../hosting-worker/index.ts", import.meta.url).href;
  const { requestedRange } = await import(modulePath);
  assert.equal(requestedRange({ header: null, size: 1000 }), null);
  assert.deepEqual(requestedRange({ header: "bytes=0-99", size: 1000 }), { offset: 0, length: 100 });
  assert.deepEqual(requestedRange({ header: "bytes=900-", size: 1000 }), { offset: 900, length: 100 });
  assert.deepEqual(requestedRange({ header: "bytes=-50", size: 1000 }), { offset: 950, length: 50 });
  assert.deepEqual(requestedRange({ header: "bytes=900-9000", size: 1000 }), { offset: 900, length: 100 });
  for (const header of ["bytes=1000-", "bytes=30-10", "bytes=0-1,4-5", "bytes=-0", "bytes=-", "bytes=1.5-2", "bytes=999999999999999999999-"]) {
    assert.throws(() => requestedRange({ header, size: 1000 }));
  }
});

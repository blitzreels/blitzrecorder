import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { inspectVideo, transcode } from "../../lib/hosting/transcode";

const exec = promisify(execFile);

test("fast-start H264/AAC can be watched before HLS and both renditions decode with audio", { timeout: 90_000 }, async () => {
  const folder = await mkdtemp(path.join(tmpdir(), "hosting-media-test-"));
  try {
    const source = path.join(folder, "video.mp4");
    await exec("ffmpeg", ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1080x1920:rate=24",
      "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "libx264", "-preset", "ultrafast",
      "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", source]);
    const info = await inspectVideo(source);
    assert.equal(info.progressive, true);
    const destination = path.join(folder, "hls");
    const files = await transcode({ source, destination, info, signal: new AbortController().signal });
    assert.ok(files.every((file) => !file.path.includes("v480")));
    const master = await readFile(path.join(destination, "master.m3u8"), "utf8");
    assert.match(master, /RESOLUTION=720x1280/);
    assert.match(master, /RESOLUTION=1080x1920/);
    for (const level of [720, 1080]) {
      await exec("ffmpeg", ["-hide_banner", "-loglevel", "error", "-i", path.join(destination, `v${level}/index.m3u8`),
        "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"], { timeout: 30_000 });
    }
    const slowStart = path.join(folder, "tail-metadata.mp4");
    await exec("ffmpeg", ["-hide_banner", "-loglevel", "error", "-i", source, "-c", "copy", slowStart]);
    assert.equal((await inspectVideo(slowStart)).progressive, false);
  } finally { await rm(folder, { recursive: true, force: true }); }
});

test("small silent sources stay small and cancellation never publishes a finished playlist", { timeout: 30_000 }, async () => {
  const folder = await mkdtemp(path.join(tmpdir(), "hosting-small-test-"));
  try {
    const source = path.join(folder, "video.mp4");
    await exec("ffmpeg", ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=400x300:rate=24",
      "-t", "1", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", source]);
    const info = await inspectVideo(source);
    assert.equal(info.progressive, true);
    const destination = path.join(folder, "hls");
    await transcode({ source, destination, info, signal: new AbortController().signal });
    assert.match(await readFile(path.join(destination, "master.m3u8"), "utf8"), /RESOLUTION=400x300/);
    const stop = new AbortController();
    stop.abort();
    const cancelled = path.join(folder, "cancelled");
    await assert.rejects(transcode({ source, destination: cancelled, info, signal: stop.signal }));
    await assert.rejects(readFile(path.join(cancelled, "master.m3u8")));
  } finally { await rm(folder, { recursive: true, force: true }); }
});

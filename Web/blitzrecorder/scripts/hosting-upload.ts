import { open, stat } from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import { setTimeout } from "node:timers/promises";
import { inspectVideo } from "../lib/hosting/transcode";
import { parseArgs } from "node:util";
import { localVideoDetails } from "../lib/hosting/local-details";

async function main() {
  const args = parseArgs({ allowPositionals: true, options: {
    project: { type: "string" }, transcript: { type: "string" }, details: { type: "string" }, speed: { type: "string" }, help: { type: "boolean" },
  } });
  if (args.values.help) {
    console.log("Usage: npm run hosting:upload -- export.mp4 [--project project.blitzrecorder.json --speed 1.3] [--transcript transcript.json]\nOr: npm run hosting:upload -- export.mp4 --details export.details.json\nDetails: version 1, optional title, summary, language, recordedAt, transcript [{start,end,text,speaker}], chapters [{start,title,summary}].\nAll details timestamps must match the exported video. Requires HOSTING_API_ORIGIN and HOSTING_ACCESS_TOKEN.");
    return;
  }
  const file = args.positionals[0];
  const token = process.env.HOSTING_ACCESS_TOKEN;
  const origin = process.env.HOSTING_API_ORIGIN;
  if (!file || !token || !origin) throw new Error("Provide a video path, HOSTING_API_ORIGIN and HOSTING_ACCESS_TOKEN.");
  const base = new URL(origin);
  if (base.protocol !== "https:" && !["localhost", "127.0.0.1"].includes(base.hostname)) throw new Error("Hosting requires HTTPS.");
  const details = await stat(file);
  const info = await inspectVideo(file);
  if (args.values.project && !args.values.speed) throw new Error("Pass --speed with the playback speed used for this export.");
  const metadata = await localVideoDetails({ file, info, projectPath: args.values.project ?? null,
    transcriptPath: args.values.transcript ?? null, detailsPath: args.values.details ?? null, playbackRate: Number(args.values.speed ?? 1) });
  const requestKey = createHash("sha256").update(`${path.resolve(file)}:${details.size}:${details.mtimeMs}`).digest("hex");
  async function api({ route, body, method }: { route: string; body: unknown; method: "GET" | "POST" }) {
    const response = await fetch(new URL(`/api/hosting/${route}`, base), {
      method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: method === "GET" ? undefined : JSON.stringify(body), redirect: "error",
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? "Hosting request failed.");
    return result;
  }
  const asset = await api({ route: "assets", method: "POST", body: {
    title: metadata.title, bytes: details.size, duration: info.duration,
    contentType: path.extname(file).toLowerCase() === ".mov" ? "video/quicktime" : "video/mp4", requestKey,
  } });
  await api({ route: `assets/${asset.id}/details`, method: "POST", body: metadata.details });
  if (asset.status === "uploading") {
    const state = await api({ route: `assets/${asset.id}`, method: "GET", body: null });
    const uploaded = new Map<number, number>(state.uploadedParts.map((part: { number: number; bytes: number }) => [part.number, part.bytes]));
    const handle = await open(file, "r");
    try {
      for (let number = 1; number <= asset.parts; number++) {
        const offset = (number - 1) * asset.partBytes;
        const expected = Math.min(asset.partBytes, details.size - offset);
        if (uploaded.get(number) === expected) continue;
        const buffer = Buffer.allocUnsafe(expected);
        let read = 0;
        while (read < expected) {
          const chunk = await handle.read(buffer, read, expected - read, offset + read);
          if (!chunk.bytesRead) throw new Error("The export changed during upload. Start again with the finished file.");
          read += chunk.bytesRead;
        }
        for (let attempt = 0; ; attempt++) {
          try {
            const part = await api({ route: `assets/${asset.id}/parts`, method: "POST", body: { number } });
            const response = await fetch(part.url, { method: "PUT", body: buffer, redirect: "error", signal: AbortSignal.timeout(120_000) });
            if (!response.ok) throw new Error("Upload interrupted.");
            break;
          } catch (error) {
            if (attempt >= 2) throw error;
            await setTimeout(1000 * 2 ** attempt);
          }
        }
        console.log(JSON.stringify({ status: "uploading", part: number, parts: asset.parts }));
      }
    } finally { await handle.close(); }
    await api({ route: `assets/${asset.id}/complete`, method: "POST", body: {} });
  }
  let previous: string | null = null;
  const deadline = Date.now() + 2 * 60 * 60 * 1000;
  while (Date.now() < deadline) {
    const status = await api({ route: `assets/${asset.id}`, method: "GET", body: null });
    if (status.status !== previous) console.log(JSON.stringify({ id: asset.id, status: status.status }));
    previous = status.status;
    if (status.status === "ready") {
      console.log(JSON.stringify({ shareURL: new URL(status.sharePath, base).href }));
      return;
    }
    if (["failed", "revoked"].includes(status.status)) throw new Error(status.error ?? "Sharing was cancelled.");
    await setTimeout(2000);
  }
  throw new Error("Video is still processing. Run this command again to check the same upload.");
}

main().catch((error) => { console.error(error instanceof Error ? error.message : "Upload failed."); process.exitCode = 1; });

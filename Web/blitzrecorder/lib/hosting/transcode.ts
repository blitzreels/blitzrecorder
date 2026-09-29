import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, open, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { MAX_VIDEO_SECONDS, safeDeliveryPath, type HostedFile } from "./model";

const exec = promisify(execFile);

export type VideoInfo = { duration: number; width: number; height: number; hasAudio: boolean };

export type VideoInspection = VideoInfo & {
  frameRate: number | null; codec: string | null;
  title: string | null; description: string | null; recordedAt: string | null;
  progressive: boolean;
};

async function hasFastStart(file: string): Promise<boolean> {
  const handle = await open(file, "r");
  try {
    const { size } = await handle.stat();
    const header = Buffer.alloc(16);
    let position = 0;
    for (let boxes = 0; boxes < 10_000 && position + 8 <= size; boxes++) {
      const { bytesRead } = await handle.read(header, 0, 16, position);
      if (bytesRead < 8) return false;
      const type = header.toString("ascii", 4, 8);
      let length = header.readUInt32BE(0);
      if (length === 1) {
        if (bytesRead < 16) return false;
        length = Number(header.readBigUInt64BE(8));
      } else if (length === 0) length = size - position;
      if (!Number.isSafeInteger(length) || length < 8 || position + length > size) return false;
      if (type === "mdat") return false;
      if (type === "moov") return true;
      position += length;
    }
    return false;
  } finally { await handle.close(); }
}

export async function inspectVideo(file: string): Promise<VideoInspection> {
  const { stdout } = await exec("ffprobe", [
    "-v", "error", "-protocol_whitelist", "file,pipe", "-show_format", "-show_streams", "-of", "json", file,
  ], { timeout: 30_000, maxBuffer: 1024 * 1024 });
  const metadata = JSON.parse(stdout) as {
    format: { duration: string; format_name: string; tags?: Record<string, string> };
    streams: { codec_type: string; codec_name?: string; pix_fmt?: string; avg_frame_rate?: string; width: number; height: number; side_data_list?: { rotation?: number }[] }[];
  };
  if (!metadata.format.format_name.split(",").includes("mov")) throw new Error("Export an MP4 or MOV video before sharing.");
  const video = metadata.streams.find((stream) => stream.codec_type === "video");
  const duration = Number(metadata.format.duration);
  if (!video || !Number.isFinite(duration) || duration <= 0 || duration > MAX_VIDEO_SECONDS
    || !Number.isSafeInteger(video.width) || !Number.isSafeInteger(video.height)
    || video.width < 2 || video.height < 2 || video.width > 8192 || video.height > 8192) {
    throw new Error("This video cannot be processed. Export an MP4 up to one hour long.");
  }
  const rotated = Math.abs(video.side_data_list?.find((side) => side.rotation !== undefined)?.rotation ?? 0) % 180 === 90;
  const [numerator, denominator] = (video.avg_frame_rate ?? "0/0").split("/").map(Number);
  const fps = numerator / denominator;
  const tags = metadata.format.tags ?? {};
  const created = tags.creation_time;
  const progressive = video.codec_name === "h264" && video.pix_fmt === "yuv420p"
    && Math.min(video.width, video.height) <= 1080 && Math.max(video.width, video.height) <= 1920
    && metadata.streams.filter((stream) => stream.codec_type === "video").length === 1
    && metadata.streams.filter((stream) => stream.codec_type === "audio").every((stream) => stream.codec_name === "aac")
    && tags.major_brand?.trim() !== "qt" && await hasFastStart(file);
  return { duration, width: rotated ? video.height : video.width, height: rotated ? video.width : video.height,
    hasAudio: metadata.streams.some((stream) => stream.codec_type === "audio"),
    frameRate: Number.isFinite(fps) && fps > 0 && fps <= 240 ? fps : null, codec: video.codec_name ?? null, progressive,
    title: tags.title?.trim().slice(0, 160) || null,
    description: (tags.description ?? tags.comment)?.trim().slice(0, 10000) || null,
    recordedAt: created && Number.isFinite(Date.parse(created)) ? new Date(created).toISOString() : null };
}

export function renditions(info: VideoInfo) {
  const portrait = info.height > info.width;
  const shortSide = Math.min(info.width, info.height);
  const levels = shortSide > 720 ? [720, 1080] : [720];
  return levels.map((level) => {
    const scale = Math.min(1, level / shortSide);
    const width = Math.max(2, Math.floor(info.width * scale / 2) * 2);
    const height = Math.max(2, Math.floor(info.height * scale / 2) * 2);
    const maxRate = level === 1080 ? 6_000_000 : level === 720 ? 3_000_000 : 1_400_000;
    return { name: `v${level}`, width, height, maxRate, portrait };
  });
}

export async function transcode({ source, destination, info, signal }: {
  source: string; destination: string; info: VideoInfo; signal: AbortSignal;
}): Promise<HostedFile[]> {
  await mkdir(destination, { recursive: true });
  const ladder = renditions(info);
  const args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe",
    "-threads", "2", "-i", source, "-filter_complex_threads", "1"];
  const filters = ladder.length > 1
    ? [`[0:v:0]split=${ladder.length}${ladder.map((_, index) => `[in${index}]`).join("")}`] : [];
  for (const [index, level] of ladder.entries()) {
    filters.push(`${ladder.length > 1 ? `[in${index}]` : "[0:v:0]"}scale=${level.width}:${level.height}:flags=lanczos,setsar=1[out${index}]`);
  }
  args.push("-filter_complex", filters.join(";"));
  for (const [index, level] of ladder.entries()) {
    const directory = path.join(destination, level.name);
    await mkdir(directory);
    args.push(
      "-map", `[out${index}]`, "-map", "0:a:0?", "-sn", "-dn", "-map_metadata", "-1",
      "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-profile:v", "high", "-pix_fmt", "yuv420p",
      "-maxrate", String(level.maxRate), "-bufsize", String(level.maxRate * 2), "-threads", "1",
      "-force_key_frames", "expr:gte(t,n_forced*4)", "-sc_threshold", "0",
      "-c:a", "aac", "-b:a", "160k", "-ac", "2", "-ar", "48000",
      "-f", "hls", "-hls_time", "4", "-hls_playlist_type", "vod", "-hls_segment_type", "fmp4",
      "-hls_fmp4_init_filename", "init.mp4", "-hls_flags", "independent_segments",
      "-hls_segment_filename", path.join(directory, "segment-%06d.m4s"), path.join(directory, "index.m3u8"),
    );
  }
  await exec("ffmpeg", args, { signal, timeout: 2 * 60 * 60 * 1000, maxBuffer: 1024 * 1024 });
  await writeFile(path.join(destination, "master.m3u8"), [
    "#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-INDEPENDENT-SEGMENTS",
    ...ladder.flatMap((level) => [
      `#EXT-X-STREAM-INF:BANDWIDTH=${Math.ceil((level.maxRate + (info.hasAudio ? 160_000 : 0)) * 1.15)},RESOLUTION=${level.width}x${level.height}`,
      `${level.name}/index.m3u8`,
    ]), "",
  ].join("\n"));
  await exec("ffmpeg", [
    "-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe", "-ss", String(Math.min(1, info.duration / 2)),
    "-i", source, "-frames:v", "1", "-vf", "scale=960:960:force_original_aspect_ratio=decrease", "-q:v", "3",
    path.join(destination, "poster.jpg"),
  ], { signal, timeout: 30_000 });
  const files: HostedFile[] = [];
  for (const relative of await readdir(destination, { recursive: true })) {
    const details = await stat(path.join(destination, relative));
    if (!details.isFile()) continue;
    if (!safeDeliveryPath(relative)) throw new Error("Unexpected streaming output.");
    if (relative.endsWith(".m3u8")) {
      const text = await readFile(path.join(destination, relative), "utf8");
      if (text.includes(source) || text.includes(destination) || /https?:\/\//.test(text)) throw new Error("Invalid streaming playlist.");
    }
    files.push({ path: relative, bytes: details.size, contentType: relative.endsWith(".m3u8") ? "application/vnd.apple.mpegurl"
      : relative.endsWith(".jpg") ? "image/jpeg" : relative.endsWith(".m4s") ? "video/iso.segment" : "video/mp4" });
  }
  return files;
}

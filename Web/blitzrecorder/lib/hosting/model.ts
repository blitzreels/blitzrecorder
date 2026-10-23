import { createHash, randomBytes } from "node:crypto";
import type { VideoDetails } from "./details";
import { sharePath } from "./paths";

export const PART_BYTES = 16 * 1024 * 1024;
export const UPLOAD_SECONDS = 24 * 60 * 60;
export const MAX_VIDEO_SECONDS = 60 * 60;
export const MAX_SOURCE_BYTES = 5 * 1024 ** 3;
/** Direct MP4s skip processing, so only R2's 10,000-part multipart limit and the plan quotas bound them. */
export const MAX_DIRECT_BYTES = 10_000 * PART_BYTES;
export const MAX_DIRECT_SECONDS = 24 * 60 * 60;
export const DELIVERY_TTL_SECONDS = 10;
export const POSTER_MAX_BYTES = 1024 ** 2;
/** The app's link-preview clip: the first minute at up to 720p, about 12 MB. */
export const PREVIEW_MAX_BYTES = 16 * 1024 ** 2;
/** The media worker the Mac app deploys into the owner's own Cloudflare account. */
export const OWN_STORAGE_ORIGIN = /^https:\/\/blitzrecorder-media\.[a-z0-9-]{1,63}\.workers\.dev$/;

export class HostingError extends Error {
  readonly status: number;

  constructor({ status, message }: { status: number; message: string }) {
    super(message);
    this.status = status;
  }
}

export function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new HostingError({ status: 503, message: "Video hosting is not configured yet." });
  return value;
}

export function assertHostingEnabled() {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") {
    throw new HostingError({ status: 503, message: "Video hosting is not available yet." });
  }
}

export function tokenHash(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function newAccessToken(): string {
  return `brh_${randomBytes(32).toString("base64url")}`;
}

export type AssetStatus = "uploading" | "queued" | "processing" | "ready" | "failed" | "revoked";

export type HostedFile = { path: string; bytes: number; contentType: string };

export type HostedAsset = {
  id: string;
  slug: string;
  account_id: string;
  request_key: string;
  title: string;
  status: AssetStatus;
  content_type: string;
  source_key: string;
  upload_id: string | null;
  declared_bytes: string;
  declared_seconds: number;
  reserved_bytes: string;
  stored_bytes: string;
  expires_at: Date;
  lease_token: string | null;
  lease_until: Date | null;
  processing_progress?: number | null;
  attempts: number;
  stream_prefix: string | null;
  files: HostedFile[];
  duration: number | null;
  width: number | null;
  height: number | null;
  frame_rate: number | null;
  video_codec: string | null;
  viewer_details: VideoDetails;
  media_origin: string | null;
  listed: boolean;
  error: string | null;
  created_at: Date;
};

export type HostingAccount = {
  id: string;
  email: string | null;
  active_until: Date;
  storage_limit: string;
};

export type UploadInput = {
  title: string;
  bytes: number;
  duration: number;
  contentType: "video/mp4" | "video/quicktime";
  requestKey: string;
  mediaOrigin: string | null;
  video?: PlayableVideo;
};

export type PlayableVideo = { width: number; height: number; frameRate: number | null };

function parsePlayableVideo(value: unknown): PlayableVideo {
  const video = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const { width, height, frameRate } = video;
  if (typeof width !== "number" || typeof height !== "number" || !Number.isSafeInteger(width) || !Number.isSafeInteger(height)
    || Math.min(width, height) < 2 || Math.min(width, height) > 1080 || Math.max(width, height) > 1920) {
    throw new HostingError({ status: 400, message: "Share a video up to 1080p." });
  }
  if (frameRate !== null && (typeof frameRate !== "number" || !Number.isFinite(frameRate) || frameRate <= 0 || frameRate > 240)) {
    throw new HostingError({ status: 400, message: "Invalid video frame rate." });
  }
  return { width, height, frameRate };
}

export function parseUploadInput(body: unknown): UploadInput {
  if (!body || typeof body !== "object") throw new HostingError({ status: 400, message: "Invalid upload." });
  const value = body as Record<string, unknown>;
  if (typeof value.title !== "string" || !value.title.trim() || value.title.trim().length > 160) {
    throw new HostingError({ status: 400, message: "Choose a title of 1–160 characters." });
  }
  const direct = value.video !== undefined;
  if (typeof value.bytes !== "number" || !Number.isSafeInteger(value.bytes) || value.bytes < 16
    || value.bytes > (direct ? MAX_DIRECT_BYTES : MAX_SOURCE_BYTES)) {
    throw new HostingError({ status: 400, message: direct ? "This video is too large to share." : "Choose a video smaller than 5 GB." });
  }
  if (typeof value.duration !== "number" || !Number.isFinite(value.duration) || value.duration <= 0
    || value.duration > (direct ? MAX_DIRECT_SECONDS : MAX_VIDEO_SECONDS)) {
    throw new HostingError({ status: 400, message: direct ? "Choose a video up to 24 hours long." : "Choose a video up to one hour long." });
  }
  if (value.contentType !== "video/mp4" && value.contentType !== "video/quicktime") {
    throw new HostingError({ status: 400, message: "Choose an exported MP4 or MOV video." });
  }
  if (typeof value.requestKey !== "string" || !/^[A-Za-z0-9_-]{16,100}$/.test(value.requestKey)) {
    throw new HostingError({ status: 400, message: "A stable upload request key is required." });
  }
  const mediaOrigin = value.mediaOrigin ?? null;
  if (mediaOrigin !== null && (typeof mediaOrigin !== "string" || !OWN_STORAGE_ORIGIN.test(mediaOrigin) || !direct)) {
    throw new HostingError({ status: 400, message: "Reconnect your Cloudflare storage in BlitzRecorder and try again." });
  }
  const input: UploadInput = { title: value.title.trim(), bytes: value.bytes, duration: value.duration, contentType: value.contentType,
    requestKey: value.requestKey, mediaOrigin };
  if (value.video === undefined) return input;
  if (input.contentType !== "video/mp4") throw new HostingError({ status: 400, message: "Share an MP4 video." });
  return { ...input, video: parsePlayableVideo(value.video) };
}

export function reservationBytes(input: UploadInput): number {
  if (input.video) return input.bytes + POSTER_MAX_BYTES + PREVIEW_MAX_BYTES;
  return input.bytes + Math.ceil(input.duration * 12_000_000 / 8 * 1.3) + 10 * 1024 ** 2;
}

export function partSize({ bytes, number }: { bytes: number; number: number }): number {
  if (!Number.isSafeInteger(number) || number < 1 || number > Math.ceil(bytes / PART_BYTES)) {
    throw new HostingError({ status: 400, message: "Invalid upload part." });
  }
  return Math.min(PART_BYTES, bytes - (number - 1) * PART_BYTES);
}

/** The app's link-preview clip size: at most 720 on the short side and 1280 on the long one, in even pixels. */
export function previewSize({ width, height }: { width: number; height: number }) {
  const scale = Math.min(1, 720 / Math.min(width, height), 1280 / Math.max(width, height));
  return { width: Math.max(2, Math.floor(width * scale / 2) * 2), height: Math.max(2, Math.floor(height * scale / 2) * 2) };
}

export function safeDeliveryPath(path: string): boolean {
  return /^(video\.mp4|preview\.mp4|master\.m3u8|poster\.jpg|v(?:480|720|1080)\/(?:index\.m3u8|init\.mp4|segment-\d{6}\.m4s))$/.test(path);
}

export function publicAsset(asset: HostedAsset) {
  return {
    id: asset.id, title: asset.title, status: asset.status,
    sharePath: asset.status === "ready" ? sharePath(asset.slug) : null,
    duration: asset.duration, width: asset.width, height: asset.height,
    bytes: Number(asset.stored_bytes), error: asset.error,
    progress: asset.status === "processing" ? asset.processing_progress ?? null : null,
    storage: asset.media_origin ? "cloudflare" : "blitzrecorder",
    listed: asset.listed,
  };
}

/** Our videos stream from the shared media worker; own-storage videos from the owner's worker. */
export function mediaURL({ asset, path }: { asset: Pick<HostedAsset, "id" | "slug" | "media_origin">; path: string }): string {
  if (asset.media_origin) return `${asset.media_origin}/v/${asset.id}/${path}`;
  return `${new URL(required("HOSTING_MEDIA_ORIGIN")).origin}/s/${asset.slug}/${path}`;
}

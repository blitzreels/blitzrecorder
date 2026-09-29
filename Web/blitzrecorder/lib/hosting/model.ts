import { createHash, randomBytes } from "node:crypto";
import type { VideoDetails } from "./details";

export const PART_BYTES = 16 * 1024 * 1024;
export const UPLOAD_SECONDS = 24 * 60 * 60;
export const MAX_VIDEO_SECONDS = 60 * 60;
export const MAX_SOURCE_BYTES = 5 * 1024 ** 3;
export const DELIVERY_TTL_SECONDS = 10;

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
  source_ready: boolean;
  upload_id: string | null;
  declared_bytes: string;
  declared_seconds: number;
  reserved_bytes: string;
  stored_bytes: string;
  expires_at: Date;
  lease_token: string | null;
  lease_until: Date | null;
  attempts: number;
  stream_prefix: string | null;
  files: HostedFile[];
  duration: number | null;
  width: number | null;
  height: number | null;
  frame_rate: number | null;
  video_codec: string | null;
  viewer_details: VideoDetails;
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
};

export function parseUploadInput(body: unknown): UploadInput {
  if (!body || typeof body !== "object") throw new HostingError({ status: 400, message: "Invalid upload." });
  const value = body as Record<string, unknown>;
  if (typeof value.title !== "string" || !value.title.trim() || value.title.trim().length > 160) {
    throw new HostingError({ status: 400, message: "Choose a title of 1–160 characters." });
  }
  if (typeof value.bytes !== "number" || !Number.isSafeInteger(value.bytes) || value.bytes < 16 || value.bytes > MAX_SOURCE_BYTES) {
    throw new HostingError({ status: 400, message: "Choose a video smaller than 5 GB." });
  }
  if (typeof value.duration !== "number" || !Number.isFinite(value.duration) || value.duration <= 0 || value.duration > MAX_VIDEO_SECONDS) {
    throw new HostingError({ status: 400, message: "Choose a video up to one hour long." });
  }
  if (value.contentType !== "video/mp4" && value.contentType !== "video/quicktime") {
    throw new HostingError({ status: 400, message: "Choose an exported MP4 or MOV video." });
  }
  if (typeof value.requestKey !== "string" || !/^[A-Za-z0-9_-]{16,100}$/.test(value.requestKey)) {
    throw new HostingError({ status: 400, message: "A stable upload request key is required." });
  }
  return { title: value.title.trim(), bytes: value.bytes, duration: value.duration, contentType: value.contentType, requestKey: value.requestKey };
}

export function reservationBytes(input: UploadInput): number {
  return input.bytes + Math.ceil(input.duration * 12_000_000 / 8 * 1.3) + 10 * 1024 ** 2;
}

export function partSize({ bytes, number }: { bytes: number; number: number }): number {
  if (!Number.isSafeInteger(number) || number < 1 || number > Math.ceil(bytes / PART_BYTES)) {
    throw new HostingError({ status: 400, message: "Invalid upload part." });
  }
  return Math.min(PART_BYTES, bytes - (number - 1) * PART_BYTES);
}

export function safeDeliveryPath(path: string): boolean {
  return /^(master\.m3u8|poster\.jpg|v(?:480|720|1080)\/(?:index\.m3u8|init\.mp4|segment-\d{6}\.m4s))$/.test(path);
}

export function publicAsset(asset: HostedAsset) {
  const playable = asset.status !== "revoked" && (asset.source_ready || asset.status === "ready");
  return {
    id: asset.id, title: asset.title, status: playable ? "ready" : asset.status,
    streamingStatus: asset.status,
    sharePath: playable ? `/s/${asset.slug}` : null,
    duration: asset.duration, width: asset.width, height: asset.height,
    bytes: Number(asset.stored_bytes) || Number(asset.declared_bytes), error: playable ? null : asset.error,
  };
}

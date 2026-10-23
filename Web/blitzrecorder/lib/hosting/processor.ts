import { randomUUID } from "node:crypto";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { hostingPool } from "./db";
import { abortUpload, deletePrefix, downloadSource, sourceURL, uploadFile } from "./r2";
import { encodePreview, inspectVideo, InvalidVideo, PREVIEW_MAX_BYTES, transcode } from "./transcode";
import { MAX_DIRECT_SECONDS, MAX_VIDEO_SECONDS, type HostedAsset } from "./model";
import { HOSTING_PLAN } from "./plan";

export async function processNext(): Promise<boolean> {
  const lease = randomUUID();
  const claimed = await hostingPool().query<HostedAsset>(
    `UPDATE hosting_assets SET status='processing', lease_token=$1, lease_until=now()+interval '2 minutes',
       processing_progress=0, attempts=attempts+1, updated_at=now()
     WHERE id=(SELECT id FROM hosting_assets WHERE (status='queued' OR (status='processing' AND lease_until<now()))
       AND attempts<3 ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING *`, [lease]);
  const asset = claimed.rows[0];
  if (!asset) return false;
  const work = await mkdtemp(path.join(tmpdir(), "blitz-hosting-"));
  const prefix = `hosting/${asset.account_id}/${asset.id}/streams/${lease}/`;
  const abort = new AbortController();
  let heartbeatActive = false;
  let progress = 0;
  const heartbeat = setInterval(async () => {
    if (heartbeatActive) return;
    heartbeatActive = true;
    try {
      const result = await hostingPool().query(
        `UPDATE hosting_assets SET lease_until=now()+interval '2 minutes', processing_progress=$3
         WHERE id=$1 AND lease_token=$2 AND status='processing'`, [asset.id, lease, Math.round(progress * 1000) / 1000]);
      if (!result.rowCount) abort.abort();
    } catch { abort.abort(); }
    finally { heartbeatActive = false; }
  }, 20_000);
  try {
    const source = path.join(work, "source.mov");
    const destination = path.join(work, "stream");
    await downloadSource({ asset, destination: source });
    progress = 0.05;
    const info = await inspectVideo({ source, maxSeconds: MAX_VIDEO_SECONDS });
    if (info.duration > asset.declared_seconds + 1) throw new Error("The uploaded video does not match its declared duration.");
    const files = await transcode({ source, destination, info, signal: abort.signal,
      onProgress: (fraction) => { progress = 0.05 + fraction * 0.85; } });
    const bytes = files.reduce((sum, file) => sum + file.bytes, Number(asset.declared_bytes));
    if (bytes > Number(asset.reserved_bytes)) throw new Error("The video exceeds its reserved storage.");
    let uploaded = 0;
    const queue = [...files];
    const uploads = await Promise.allSettled(Array.from({ length: 8 }, async () => {
      for (let file = queue.shift(); file; file = queue.shift()) {
        try {
          abort.signal.throwIfAborted();
          await uploadFile({ key: prefix + file.path, path: path.join(destination, file.path), bytes: file.bytes, contentType: file.contentType });
        } catch (error) {
          queue.length = 0;
          throw error;
        }
        uploaded += file.bytes;
        progress = 0.9 + 0.1 * uploaded / Math.max(1, bytes - Number(asset.declared_bytes));
      }
    }));
    const failed = uploads.find((upload) => upload.status === "rejected");
    if (failed) throw failed.reason;
    const result = await hostingPool().query(
      `UPDATE hosting_assets SET status='ready', stored_bytes=$3, stream_prefix=$4, files=$5::jsonb,
       duration=$6,width=$7,height=$8,frame_rate=$9,video_codec=$10,error=NULL,lease_until=NULL,processing_progress=NULL,updated_at=now()
       WHERE id=$1 AND lease_token=$2 AND status='processing'`,
      [asset.id, lease, bytes, prefix, JSON.stringify(files), info.duration, info.width, info.height, info.frameRate, info.codec]);
    if (!result.rowCount) await deletePrefix(prefix);
  } catch (error) {
    await deletePrefix(prefix).catch(() => undefined);
    await hostingPool().query(
      `UPDATE hosting_assets SET status=CASE WHEN attempts<3 THEN 'queued' ELSE 'failed' END,
       error=$3,lease_until=NULL,processing_progress=NULL,updated_at=now() WHERE id=$1 AND lease_token=$2 AND status='processing'`,
      [asset.id, lease, error instanceof Error && error.message.startsWith("The ") ? error.message : "Video processing failed. Please upload a fresh export."]);
  } finally {
    clearInterval(heartbeat);
    await rm(work, { recursive: true, force: true });
  }
  return true;
}

/**
 * Direct MP4s go live without processing, so the worker checks them afterwards: a file longer or larger than the
 * app declared stops playing. Every video we host also gets a short MP4 for link previews.
 */
export async function checkNext(): Promise<boolean> {
  const lease = randomUUID();
  const claimed = await hostingPool().query<HostedAsset>(
    `UPDATE hosting_assets SET lease_token=$1, lease_until=now()+interval '15 minutes', check_attempts=check_attempts+1
     WHERE id=(SELECT id FROM hosting_assets WHERE status='ready' AND checked_at IS NULL AND media_origin IS NULL
       AND check_attempts<3 AND (lease_until IS NULL OR lease_until<now()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1)
     RETURNING *`, [lease]);
  const asset = claimed.rows[0];
  if (!asset) return false;
  const work = await mkdtemp(path.join(tmpdir(), "blitz-hosting-"));
  const settle = ({ sql, values }: { sql: string; values: unknown[] }) => hostingPool().query(
    `UPDATE hosting_assets SET ${sql}, checked_at=now(), lease_token=NULL, lease_until=NULL, updated_at=now()
     WHERE id=$1 AND lease_token=$2 AND status='ready'`, [asset.id, lease, ...values]);
  const reject = (message: string) => settle({ sql: "status='failed', error=$3", values: [message] });
  try {
    const source = await sourceURL(asset);
    const direct = asset.files.some((file) => file.path === "video.mp4");
    let info;
    try { info = await inspectVideo({ source, maxSeconds: direct ? MAX_DIRECT_SECONDS : MAX_VIDEO_SECONDS }); }
    catch (error) {
      if (!(error instanceof InvalidVideo)) throw error;
      await reject(error.message);
      return true;
    }
    if (direct && (info.duration > asset.declared_seconds + 1
      || Math.min(info.width, info.height) > 1080 || Math.max(info.width, info.height) > 1920)) {
      await reject("The uploaded video is longer or larger than the app reported. Share it again from BlitzRecorder.");
      return true;
    }
    if (!asset.stream_prefix) {
      await settle({ sql: "duration=$3", values: [info.duration] });
      return true;
    }
    const preview = path.join(work, "preview.mp4");
    await encodePreview({ source, destination: preview, info, signal: AbortSignal.timeout(10 * 60_000) });
    const bytes = (await stat(preview)).size;
    if (bytes > PREVIEW_MAX_BYTES) throw new Error("The link preview came out too large.");
    await uploadFile({ key: `${asset.stream_prefix}preview.mp4`, path: preview, bytes, contentType: "video/mp4" });
    await settle({ sql: "files=files || $3::jsonb, stored_bytes=stored_bytes+$4, duration=$5",
      values: [JSON.stringify([{ path: "preview.mp4", bytes, contentType: "video/mp4" }]), bytes, info.duration] });
  } catch (error) {
    console.error("Video check failed", error instanceof Error ? error.message : "Unknown error");
    await hostingPool().query(
      "UPDATE hosting_assets SET lease_token=NULL, lease_until=now()+interval '10 minutes' WHERE id=$1 AND lease_token=$2",
      [asset.id, lease]);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
  return true;
}

export async function cleanupExpired() {
  await hostingPool().query(
    `UPDATE hosting_assets SET status='revoked',updated_at=now() WHERE status<>'revoked' AND media_origin IS NULL AND account_id IN
     (SELECT id FROM hosting_accounts WHERE active_until<=now()
      AND COALESCE(inactive_since,active_until)<now()-$1*interval '1 day')`, [HOSTING_PLAN.retentionDaysAfterExpiry]);
  await hostingPool().query(
    "UPDATE hosting_assets SET status='revoked',updated_at=now() WHERE status='uploading' AND expires_at<now()");
  await hostingPool().query(
    "UPDATE hosting_assets SET status='failed',error='Video processing was interrupted.',updated_at=now() WHERE status='processing' AND lease_until<now() AND attempts>=3");
  await hostingPool().query(
    "UPDATE hosting_assets SET status='revoked',updated_at=now() WHERE status='failed' AND media_origin IS NULL AND updated_at<now()-$1*interval '1 day'",
    [HOSTING_PLAN.failedRetentionDays]);
  const expired = await hostingPool().query<HostedAsset>(
    "SELECT * FROM hosting_assets WHERE status='revoked' AND (lease_until IS NULL OR lease_until<now()) LIMIT 50");
  for (const asset of expired.rows) {
    if (!asset.media_origin) {
      await abortUpload(asset);
      await deletePrefix(`hosting/${asset.account_id}/${asset.id}/`);
    }
    await hostingPool().query("DELETE FROM hosting_assets WHERE id=$1 AND status='revoked'", [asset.id]);
  }
}

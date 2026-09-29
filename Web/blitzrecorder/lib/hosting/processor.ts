import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { hostingPool } from "./db";
import { abortUpload, deletePrefix, downloadSource, uploadFile } from "./r2";
import { inspectVideo, transcode } from "./transcode";
import type { HostedAsset } from "./model";
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
    const info = await inspectVideo(source);
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

export async function cleanupExpired() {
  await hostingPool().query(
    `UPDATE hosting_assets SET status='revoked',updated_at=now() WHERE status<>'revoked' AND account_id IN
     (SELECT id FROM hosting_accounts WHERE active_until<=now()
      AND COALESCE(inactive_since,active_until)<now()-$1*interval '1 day')`, [HOSTING_PLAN.retentionDaysAfterExpiry]);
  await hostingPool().query(
    "UPDATE hosting_assets SET status='revoked',updated_at=now() WHERE status='uploading' AND expires_at<now()");
  await hostingPool().query(
    "UPDATE hosting_assets SET status='failed',error='Video processing was interrupted.',updated_at=now() WHERE status='processing' AND lease_until<now() AND attempts>=3");
  const expired = await hostingPool().query<HostedAsset>(
    "SELECT * FROM hosting_assets WHERE status='revoked' AND (lease_until IS NULL OR lease_until<now()) LIMIT 50");
  for (const asset of expired.rows) {
    await abortUpload(asset);
    await deletePrefix(`hosting/${asset.account_id}/${asset.id}/`);
    await hostingPool().query("DELETE FROM hosting_assets WHERE id=$1 AND status='revoked'", [asset.id]);
  }
}

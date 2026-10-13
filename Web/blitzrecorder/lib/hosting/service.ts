import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { hostingPool, transaction, ensureAssetColumns } from "./db";
import {
  assertHostingEnabled, HostingError, PART_BYTES, POSTER_MAX_BYTES, UPLOAD_SECONDS, parseUploadInput,
  publicAsset, required, reservationBytes, type HostedAsset, type HostedFile, type HostingAccount,
} from "./model";
import { createUpload, completeUpload, objectBytes, signPart, uploadData, uploadParts, signalJob } from "./r2";
import { parseVideoDetails } from "./details";
import { ownStorageBytes } from "./own-storage";
import { accountForToken } from "./account";
import { HOSTING_PLAN } from "./plan";
import { setVideoListing } from "./web-session";
import type { PoolClient } from "pg";

async function requireUploadAllowance({ db, accountID, duration }: { db: PoolClient; accountID: string; duration: number }) {
  const usage = (await db.query<{ seconds: number }>(
    "SELECT COALESCE(SUM(seconds),0) AS seconds FROM hosting_upload_usage WHERE account_id=$1 AND created_at>now()-$2*interval '1 day'",
    [accountID, HOSTING_PLAN.uploadWindowDays])).rows[0].seconds;
  if (Number(usage) + duration > HOSTING_PLAN.uploadSeconds) {
    throw new HostingError({ status: 429, message: "Your plan includes 5 hours of uploads per 30 days. Existing videos remain available; try again when your allowance renews." });
  }
}

export async function updateDetails({ account, id, body }: { account: HostingAccount; id: string; body: unknown }) {
  const asset = await ownedAsset({ account, id });
  if (!asset.media_origin) requirePaid(account);
  if (asset.status === "revoked") throw new HostingError({ status: 409, message: "This video has been removed." });
  let details;
  try { details = parseVideoDetails({ value: body, duration: asset.duration ?? asset.declared_seconds }); }
  catch (error) { throw new HostingError({ status: 400, message: error instanceof Error ? error.message : "Invalid video details." }); }
  const updated = await hostingPool().query(
    "UPDATE hosting_assets SET viewer_details=$3::jsonb,updated_at=now() WHERE id=$1 AND account_id=$2 AND status<>'revoked' RETURNING id",
    [id, account.id, JSON.stringify(details)]);
  if (!updated.rowCount) throw new HostingError({ status: 409, message: "This video has been removed." });
  return { saved: true };
}

export async function authenticate(request: Request): Promise<HostingAccount> {
  assertHostingEnabled();
  const token = request.headers.get("authorization")?.match(/^Bearer (brh_[A-Za-z0-9_-]{43})$/)?.[1];
  if (!token) throw new HostingError({ status: 401, message: "Connect your hosting account to continue." });
  const account = await accountForToken(token);
  if (!account) throw new HostingError({ status: 401, message: "Your hosting connection has expired." });
  await ensureAssetColumns();
  return account;
}

function requirePaid(account: HostingAccount) {
  if (account.active_until.getTime() <= Date.now()) {
    throw new HostingError({ status: 402, message: "An active video hosting subscription is required." });
  }
}

export async function ownedAsset({ account, id }: { account: HostingAccount; id: string }): Promise<HostedAsset> {
  if (!/^[a-f0-9-]{36}$/.test(id)) throw new HostingError({ status: 404, message: "Video not found." });
  const result = await hostingPool().query<HostedAsset>(
    "SELECT * FROM hosting_assets WHERE id = $1 AND account_id = $2", [id, account.id]);
  if (!result.rows[0]) throw new HostingError({ status: 404, message: "Video not found." });
  return result.rows[0];
}

export async function beginUpload({ account, body }: { account: HostingAccount; body: unknown }) {
  const input = parseUploadInput(body);
  const asset = await transaction(async (db) => {
    const current = await db.query<HostingAccount>("SELECT * FROM hosting_accounts WHERE id = $1 FOR UPDATE", [account.id]);
    const own = input.mediaOrigin !== null;
    if (!own) requirePaid(current.rows[0]);
    const prior = await db.query<HostedAsset>(
      "SELECT * FROM hosting_assets WHERE account_id = $1 AND request_key = $2", [account.id, input.requestKey]);
    if (prior.rows[0]) {
      const saved = prior.rows[0];
      if (Number(saved.declared_bytes) !== input.bytes || saved.declared_seconds !== input.duration || saved.title !== input.title
        || saved.content_type !== input.contentType || saved.media_origin !== input.mediaOrigin) {
        throw new HostingError({ status: 409, message: "This upload request belongs to another file." });
      }
      return saved;
    }
    const reservation = reservationBytes(input);
    if (!own) {
      await requireUploadAllowance({ db, accountID: account.id, duration: input.duration });
      const usage = await db.query<{ bytes: string }>(
        `SELECT COALESCE(SUM(CASE WHEN stored_bytes > 0 THEN stored_bytes ELSE reserved_bytes END),0)::text AS bytes
         FROM hosting_assets WHERE account_id = $1 AND media_origin IS NULL`, [account.id]);
      if (Number(usage.rows[0].bytes) + reservation > Number(current.rows[0].storage_limit)) {
        throw new HostingError({ status: 413, message: "Your hosting storage is full. Remove a video or increase your plan." });
      }
    }
    const id = randomUUID();
    const prefix = input.video && !own ? `hosting/${account.id}/${id}/streams/${randomUUID()}/` : null;
    const sourceKey = own ? `own/${id}/video.mp4` : prefix ? `${prefix}video.mp4` : `hosting/${account.id}/${id}/source`;
    const created = await db.query<HostedAsset>(
      `INSERT INTO hosting_assets (id,slug,account_id,request_key,title,status,content_type,source_key,
       declared_bytes,declared_seconds,reserved_bytes,expires_at,stream_prefix,width,height,frame_rate,video_codec,media_origin)
       VALUES ($1,$2,$3,$4,$5,'uploading',$6,$7,$8,$9,$10,now() + $11 * interval '1 second',$12,$13,$14,$15,$16,$17) RETURNING *`,
      [id, randomBytes(18).toString("base64url"), account.id, input.requestKey, input.title, input.contentType,
        sourceKey, input.bytes, input.duration, reservation, UPLOAD_SECONDS,
        prefix, input.video?.width ?? null, input.video?.height ?? null, input.video?.frameRate ?? null, input.video ? "h264" : null,
        input.mediaOrigin]);
    return created.rows[0];
  });
  if (asset.status === "uploading" && !asset.upload_id && !asset.media_origin) {
    await transaction(async (db) => {
      const locked = (await db.query<HostedAsset>("SELECT * FROM hosting_assets WHERE id = $1 FOR UPDATE", [asset.id])).rows[0];
      if (locked.status !== "uploading" || locked.upload_id) return;
      const uploadID = await createUpload(locked);
      await db.query("UPDATE hosting_assets SET upload_id = $2, updated_at = now() WHERE id = $1", [asset.id, uploadID]);
    });
  }
  return { ...publicAsset(await ownedAsset({ account, id: asset.id })), partBytes: PART_BYTES, parts: Math.ceil(input.bytes / PART_BYTES) };
}

export async function preparePart({ account, id, number }: { account: HostingAccount; id: string; number: number }) {
  requirePaid(account);
  const asset = await ownedAsset({ account, id });
  requireHostedByUs(asset);
  if (asset.status !== "uploading" || !asset.upload_id || asset.expires_at.getTime() <= Date.now()) {
    throw new HostingError({ status: 409, message: "This upload is no longer active." });
  }
  return signPart({ asset, number });
}

export async function uploadPoster({ account, id, body }: { account: HostingAccount; id: string; body: unknown }) {
  requirePaid(account);
  const asset = await ownedAsset({ account, id });
  requireHostedByUs(asset);
  if (asset.status !== "uploading" || !asset.stream_prefix) throw new HostingError({ status: 409, message: "This upload is no longer active." });
  const encoded = (body as { jpeg?: unknown } | null)?.jpeg;
  const data = typeof encoded === "string" ? Buffer.from(encoded, "base64") : Buffer.alloc(0);
  if (data.length < 4 || data.length > POSTER_MAX_BYTES || data[0] !== 0xff || data[1] !== 0xd8 || data[2] !== 0xff) {
    throw new HostingError({ status: 400, message: "Invalid poster image." });
  }
  await uploadData({ key: `${asset.stream_prefix}poster.jpg`, data, contentType: "image/jpeg" });
  return { saved: true };
}

export async function resumeUpload({ account, id }: { account: HostingAccount; id: string }) {
  const asset = await ownedAsset({ account, id });
  const parts = asset.status === "uploading" && asset.upload_id && !asset.media_origin ? await uploadParts(asset) : [];
  return { ...publicAsset(asset), uploadedParts: parts.map((part) => ({ number: part.PartNumber, bytes: part.Size })) };
}

export async function finishUpload({ account, id }: { account: HostingAccount; id: string }) {
  const owned = await ownedAsset({ account, id });
  if (owned.media_origin) return finishOwnUpload(owned);
  requirePaid(account);
  const result = await transaction(async (db) => {
    const current = (await db.query<HostingAccount>("SELECT * FROM hosting_accounts WHERE id=$1 FOR UPDATE", [account.id])).rows[0];
    requirePaid(current);
    const asset = (await db.query<HostedAsset>("SELECT * FROM hosting_assets WHERE id = $1 FOR UPDATE", [id])).rows[0];
    if (["queued", "processing", "ready"].includes(asset.status)) return publicAsset(asset);
    if (asset.status !== "uploading" || !asset.upload_id || asset.expires_at.getTime() <= Date.now()) {
      throw new HostingError({ status: 409, message: "This upload is no longer active." });
    }
    await requireUploadAllowance({ db, accountID: account.id, duration: asset.declared_seconds });
    await completeUpload(asset);
    await db.query("INSERT INTO hosting_upload_usage(asset_id,account_id,seconds) VALUES($1,$2,$3)",
      [asset.id, account.id, asset.declared_seconds]);
    if (asset.stream_prefix) {
      const posterBytes = await objectBytes(`${asset.stream_prefix}poster.jpg`);
      const files: HostedFile[] = [{ path: "video.mp4", bytes: Number(asset.declared_bytes), contentType: "video/mp4" },
        ...(posterBytes ? [{ path: "poster.jpg", bytes: posterBytes, contentType: "image/jpeg" }] : [])];
      const ready = await db.query<HostedAsset>(
        `UPDATE hosting_assets SET status='ready', files=$2::jsonb, stored_bytes=$3, duration=declared_seconds, updated_at=now()
         WHERE id=$1 RETURNING *`, [id, JSON.stringify(files), files.reduce((sum, file) => sum + file.bytes, 0)]);
      return publicAsset(ready.rows[0]);
    }
    const updated = await db.query<HostedAsset>(
      "UPDATE hosting_assets SET status = 'queued', updated_at = now() WHERE id = $1 RETURNING *", [id]);
    return publicAsset(updated.rows[0]);
  });
  if (["queued", "processing"].includes(result.status)) await signalJob(id);
  return result;
}

function requireHostedByUs(asset: HostedAsset) {
  if (asset.media_origin) throw new HostingError({ status: 409, message: "This video uploads to your Cloudflare storage." });
}

/** The Mac app uploads straight to the owner's worker; we only confirm the file is there before publishing the link. */
async function finishOwnUpload(asset: HostedAsset) {
  if (["ready", "failed", "revoked"].includes(asset.status)) return publicAsset(asset);
  if (asset.expires_at.getTime() <= Date.now()) throw new HostingError({ status: 409, message: "This upload is no longer active." });
  const origin = asset.media_origin!;
  const [video, poster] = await Promise.all([
    ownStorageBytes({ origin, id: asset.id, path: "video.mp4" }),
    ownStorageBytes({ origin, id: asset.id, path: "poster.jpg" }),
  ]);
  if (video !== Number(asset.declared_bytes)) {
    throw new HostingError({ status: 409, message: "Your Cloudflare storage doesn’t have the whole video yet. Resume the upload." });
  }
  const files: HostedFile[] = [{ path: "video.mp4", bytes: video, contentType: "video/mp4" },
    ...(poster ? [{ path: "poster.jpg", bytes: poster, contentType: "image/jpeg" }] : [])];
  const ready = await hostingPool().query<HostedAsset>(
    `UPDATE hosting_assets SET status='ready', files=$2::jsonb, stored_bytes=$3, duration=declared_seconds, updated_at=now()
     WHERE id=$1 AND status='uploading' RETURNING *`, [asset.id, JSON.stringify(files), files.reduce((sum, file) => sum + file.bytes, 0)]);
  return publicAsset(ready.rows[0] ?? await ownedAssetByID(asset.id));
}

async function ownedAssetByID(id: string): Promise<HostedAsset> {
  return (await hostingPool().query<HostedAsset>("SELECT * FROM hosting_assets WHERE id=$1", [id])).rows[0];
}

/** Hides or restores the public link without touching the file. Same rule as the web library. */
export async function setAssetListing({ account, id, body }: { account: HostingAccount; id: string; body: unknown }) {
  const asset = await ownedAsset({ account, id });
  const listed = (body as { listed?: unknown } | null)?.listed;
  if (typeof listed !== "boolean") throw new HostingError({ status: 400, message: "Choose whether the link is listed." });
  if (!await setVideoListing({ account, slug: asset.slug, listed })) {
    throw new HostingError({ status: 409, message: "Only ready videos can be listed. Refresh and try again." });
  }
  return publicAsset(await ownedAsset({ account, id }));
}

export async function revokeAsset({ account, id }: { account: HostingAccount; id: string }) {
  await ownedAsset({ account, id });
  await hostingPool().query("UPDATE hosting_assets SET status = 'revoked', updated_at = now() WHERE id = $1 AND account_id = $2", [id, account.id]);
  return { revoked: true };
}

export async function listAssets(account: HostingAccount) {
  const rows = await hostingPool().query<HostedAsset>(
    "SELECT * FROM hosting_assets WHERE account_id = $1 AND status <> 'revoked' ORDER BY created_at DESC LIMIT 100", [account.id]);
  return { assets: rows.rows.map(publicAsset), activeUntil: account.active_until.toISOString(), storageLimit: Number(account.storage_limit) };
}

export async function sharedAsset(slug: string): Promise<HostedAsset | null> {
  assertHostingEnabled();
  if (!/^[A-Za-z0-9_-]{24}$/.test(slug)) return null;
  await ensureAssetColumns();
  const result = await hostingPool().query<HostedAsset>(
    `SELECT assets.* FROM hosting_assets assets JOIN hosting_accounts accounts ON accounts.id = assets.account_id
     WHERE assets.slug = $1 AND assets.status = 'ready' AND assets.listed
       AND (assets.media_origin IS NOT NULL OR accounts.active_until > now())`, [slug]);
  return result.rows[0] ?? null;
}

export function authenticateDelivery(request: Request) {
  const expected = Buffer.from(`Bearer ${required("HOSTING_DELIVERY_SECRET")}`);
  const provided = Buffer.from(request.headers.get("authorization") ?? "");
  if (expected.length !== provided.length || !timingSafeEqual(expected, provided)) {
    throw new HostingError({ status: 401, message: "Not authorized." });
  }
}

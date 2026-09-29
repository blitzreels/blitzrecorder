import {
  S3Client, CreateMultipartUploadCommand, UploadPartCommand, ListPartsCommand,
  CompleteMultipartUploadCommand, HeadObjectCommand, AbortMultipartUploadCommand,
  GetObjectCommand, PutObjectCommand, ListObjectsV2Command, DeleteObjectsCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { createReadStream, createWriteStream } from "node:fs";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { HostingError, PART_BYTES, partSize, required, type HostedAsset } from "./model";

let client: S3Client | null = null;

export function r2(): S3Client {
  client ??= new S3Client({
    region: "auto", endpoint: `https://${required("HOSTING_R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: required("HOSTING_R2_ACCESS_KEY_ID"), secretAccessKey: required("HOSTING_R2_SECRET_ACCESS_KEY") },
    requestChecksumCalculation: "WHEN_REQUIRED", responseChecksumValidation: "WHEN_REQUIRED",
  });
  return client;
}

function bucket() { return required("HOSTING_R2_BUCKET"); }

export async function createUpload(asset: HostedAsset): Promise<string> {
  const result = await r2().send(new CreateMultipartUploadCommand({
    Bucket: bucket(), Key: asset.source_key, ContentType: asset.content_type,
    Metadata: { asset: asset.id }, CacheControl: "private, no-store",
  }));
  if (!result.UploadId) throw new HostingError({ status: 502, message: "Could not start the upload." });
  return result.UploadId;
}

export async function signPart({ asset, number }: { asset: HostedAsset; number: number }) {
  const bytes = partSize({ bytes: Number(asset.declared_bytes), number });
  const url = await getSignedUrl(r2(), new UploadPartCommand({
    Bucket: bucket(), Key: asset.source_key, UploadId: asset.upload_id!, PartNumber: number, ContentLength: bytes,
  }), { expiresIn: 900, signableHeaders: new Set(["content-length"]) });
  return { number, bytes, url, expiresIn: 900 };
}

export async function uploadParts(asset: HostedAsset) {
  const parts: { PartNumber: number; ETag: string; Size: number }[] = [];
  let marker: string | undefined;
  do {
    const result = await r2().send(new ListPartsCommand({
      Bucket: bucket(), Key: asset.source_key, UploadId: asset.upload_id!, PartNumberMarker: marker,
    }));
    for (const part of result.Parts ?? []) {
      if (part.PartNumber && part.ETag && part.Size !== undefined) {
        parts.push({ PartNumber: part.PartNumber, ETag: part.ETag, Size: part.Size });
      }
    }
    marker = result.IsTruncated ? result.NextPartNumberMarker : undefined;
  } while (marker);
  return parts;
}

export async function completeUpload(asset: HostedAsset) {
  try {
    const existing = await r2().send(new HeadObjectCommand({ Bucket: bucket(), Key: asset.source_key }));
    if (existing.ContentLength === Number(asset.declared_bytes) && existing.Metadata?.asset === asset.id) return;
    throw new HostingError({ status: 409, message: "Uploaded file size does not match." });
  } catch (error) {
    if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode !== 404) throw error;
  }
  const parts = await uploadParts(asset);
  const expected = Math.ceil(Number(asset.declared_bytes) / PART_BYTES);
  if (parts.length !== expected || parts.some((part, index) =>
    part.PartNumber !== index + 1 || part.Size !== partSize({ bytes: Number(asset.declared_bytes), number: index + 1 }))) {
    throw new HostingError({ status: 409, message: "Some upload parts are missing or incomplete. Resume the upload." });
  }
  await r2().send(new CompleteMultipartUploadCommand({
    Bucket: bucket(), Key: asset.source_key, UploadId: asset.upload_id!,
    MultipartUpload: { Parts: parts.map(({ ETag, PartNumber }) => ({ ETag, PartNumber })) },
  }));
}

export async function abortUpload(asset: HostedAsset) {
  if (!asset.upload_id) return;
  try {
    await r2().send(new AbortMultipartUploadCommand({ Bucket: bucket(), Key: asset.source_key, UploadId: asset.upload_id }));
  } catch (error) {
    if ((error as { name: string }).name !== "NoSuchUpload") throw error;
  }
}

export async function downloadSource({ asset, destination }: { asset: HostedAsset; destination: string }) {
  const object = await r2().send(new GetObjectCommand({ Bucket: bucket(), Key: asset.source_key }));
  if (!object.Body || object.ContentLength !== Number(asset.declared_bytes)) throw new Error("Invalid uploaded source.");
  await pipeline(object.Body as Readable, createWriteStream(destination, { flags: "wx" }));
}

export async function uploadFile({ key, path, bytes, contentType }: { key: string; path: string; bytes: number; contentType: string }) {
  await r2().send(new PutObjectCommand({
    Bucket: bucket(), Key: key, Body: createReadStream(path), ContentLength: bytes, ContentType: contentType,
    CacheControl: "public, max-age=31536000, immutable",
  }));
}

export async function deletePrefix(prefix: string) {
  if (!/^hosting\/[a-f0-9-]{36}\/[a-f0-9-]{36}\//.test(prefix)) throw new Error("Invalid cleanup prefix.");
  for (;;) {
    const result = await r2().send(new ListObjectsV2Command({ Bucket: bucket(), Prefix: prefix, MaxKeys: 1000 }));
    if (!result.Contents?.length) return;
    const deleted = await r2().send(new DeleteObjectsCommand({
      Bucket: bucket(), Delete: { Objects: result.Contents.map(({ Key }) => ({ Key: Key! })), Quiet: true },
    }));
    if (deleted.Errors?.length) throw new Error("Some hosted files could not be deleted.");
  }
}

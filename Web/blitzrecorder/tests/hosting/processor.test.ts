import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { Pool } from "pg";
import { hostingPool } from "../../lib/hosting/db";
import { r2 } from "../../lib/hosting/r2";
import { processNext } from "../../lib/hosting/processor";
import { sharedAsset } from "../../lib/hosting/service";
import { publicAsset, type HostedAsset } from "../../lib/hosting/model";

const exec = promisify(execFile);
const database = process.env.HOSTING_TEST_DATABASE_URL;

test("two uploads become playable before serialized HLS work completes, and a failed HLS upload keeps its MP4", {
  skip: !database, timeout: 90_000,
}, async () => {
  assert.ok(database && ["localhost", "127.0.0.1"].includes(new URL(database).hostname));
  const schema = `hosting_processor_${randomUUID().replaceAll("-", "")}`;
  const admin = new Pool({ connectionString: database });
  const folder = await mkdtemp(path.join(tmpdir(), "hosting-processor-test-"));
  const running: Promise<boolean>[] = [];
  try {
    await admin.query(`CREATE SCHEMA ${schema}`);
    const scoped = new URL(database);
    scoped.searchParams.set("options", `-c search_path=${schema}`);
    process.env.HOSTING_DATABASE_URL = scoped.href;
    process.env.BLITZRECORDER_HOSTING_ENABLED = "true";
    process.env.HOSTING_R2_ACCOUNT_ID = "test";
    process.env.HOSTING_R2_ACCESS_KEY_ID = "test";
    process.env.HOSTING_R2_SECRET_ACCESS_KEY = "test";
    process.env.HOSTING_R2_BUCKET = "test";
    for (const migration of ["001-hosting.sql", "002-hosting-details.sql", "006-hosting-progressive.sql"]) {
      await hostingPool().query(await readFile(new URL(`../../migrations/${migration}`, import.meta.url), "utf8"));
    }
    const source = path.join(folder, "source.mp4");
    await exec("ffmpeg", ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24",
      "-t", "8", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", source]);
    const data = await readFile(source);
    let concurrentUploads = 0;
    let peakUploads = 0;
    let failUploads = false;
    r2().middlewareStack.add((_next, context) => async (args) => {
      const input = args.input as { Body?: Readable };
      let output: { $metadata: Record<string, never>; [key: string]: unknown } = { $metadata: {} };
      if (context.commandName === "GetObjectCommand") output = { ...output, Body: Readable.from([data]), ContentLength: data.length };
      if (context.commandName === "PutObjectCommand") {
        concurrentUploads++;
        peakUploads = Math.max(peakUploads, concurrentUploads);
        try {
          if (input.Body) for await (const block of input.Body) assert.ok(block.length > 0);
          await new Promise((resolve) => setTimeout(resolve, 30));
          if (failUploads) throw new Error("Test-only upload interruption");
        } finally { concurrentUploads--; }
      }
      return { response: {}, output };
    }, { step: "initialize", name: "isolatedProcessorR2", priority: "high" });
    const account = randomUUID();
    await hostingPool().query("INSERT INTO hosting_accounts(id,token_hash,active_until,storage_limit) VALUES($1,$2,now()+interval '1 hour',50000000000)",
      [account, randomUUID()]);
    const ids = [randomUUID(), randomUUID()];
    for (const id of ids) {
      await hostingPool().query(`INSERT INTO hosting_assets(id,slug,account_id,request_key,title,status,content_type,source_key,
        declared_bytes,declared_seconds,reserved_bytes,expires_at) VALUES($1::uuid,$2,$3,$1::text,'Pipeline test','queued','video/mp4',$4,$5,8,50000000,now()+interval '1 day')`,
      [id, id.replaceAll("-", "").slice(0, 24), account, `hosting/${account}/${id}/source`, data.length]);
    }
    const started = performance.now();
    running.push(processNext(), processNext());
    let pending: HostedAsset[] = [];
    const deadline = Date.now() + 30_000;
    while (Date.now() < deadline) {
      pending = (await hostingPool().query<HostedAsset>("SELECT * FROM hosting_assets WHERE source_ready=true AND status='processing'")).rows;
      if (pending.length === 2) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(pending.length, 2);
    const playableMs = performance.now() - started;
    for (const asset of pending) {
      assert.equal(publicAsset(asset).status, "ready");
      assert.equal(asset.files.length, 0);
      assert.ok(await sharedAsset(asset.slug));
    }
    assert.deepEqual(await Promise.all(running), [true, true]);
    const hlsMs = performance.now() - started;
    assert.ok(hlsMs > playableMs);
    assert.ok(peakUploads > 1 && peakUploads <= 8);
    assert.equal(concurrentUploads, 0);
    const finished = (await hostingPool().query<HostedAsset>("SELECT * FROM hosting_assets")).rows;
    assert.ok(finished.every((asset) => asset.status === "ready" && asset.files.some((file) => file.path === "master.m3u8")));
    failUploads = true;
    await hostingPool().query("UPDATE hosting_assets SET status='queued',attempts=2,files='[]',stream_prefix=NULL WHERE id=$1", [ids[0]]);
    await processNext();
    const failed = (await hostingPool().query<HostedAsset>("SELECT * FROM hosting_assets WHERE id=$1", [ids[0]])).rows[0];
    assert.equal(failed.status, "failed");
    assert.equal(publicAsset(failed).status, "ready");
    assert.ok(await sharedAsset(failed.slug));
    assert.equal(concurrentUploads, 0);
    console.log(JSON.stringify({ playableMs: Math.round(playableMs), hlsMs: Math.round(hlsMs), peakUploads }));
  } finally {
    await Promise.allSettled(running);
    await hostingPool().end();
    await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin.end();
    await rm(folder, { recursive: true, force: true });
  }
});

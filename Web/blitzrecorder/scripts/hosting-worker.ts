import { setTimeout } from "node:timers/promises";
import { cleanupExpired, processNext } from "../lib/hosting/processor";
import { hostingPool, JOB_CHANNEL } from "../lib/hosting/db";
import { assertHostingEnabled } from "../lib/hosting/model";

async function main() {
  assertHostingEnabled();
  const once = process.argv.includes("--once");
  let wake = new AbortController();
  const listener = once ? null : await hostingPool().connect();
  if (listener) {
    listener.on("notification", () => wake.abort());
    listener.on("error", () => console.error("Hosting job listener disconnected; polling only."));
    await listener.query(`LISTEN ${JOB_CHANNEL}`);
  }
  try {
    do {
      await cleanupExpired();
      const processed = await processNext();
      if (once) break;
      if (!processed) {
        await setTimeout(5000, undefined, { signal: wake.signal }).catch(() => undefined);
        wake = new AbortController();
      }
    } while (true);
  } finally {
    listener?.release();
  }
}

main().catch((error) => { console.error(error instanceof Error ? error.message : "Hosting worker failed."); process.exitCode = 1; })
  .finally(() => hostingPool().end());

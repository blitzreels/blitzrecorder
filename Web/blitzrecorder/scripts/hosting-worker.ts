import { setTimeout } from "node:timers/promises";
import { cleanupExpired, processNext } from "../lib/hosting/processor";
import { hostingPool } from "../lib/hosting/db";
import { assertHostingEnabled } from "../lib/hosting/model";
import { pendingJobSignals, clearJobSignals } from "../lib/hosting/r2";

async function clearCompletedSignals(signals: Awaited<ReturnType<typeof pendingJobSignals>>) {
  if (!signals.length) return;
  const rows = await hostingPool().query<{ id: string; status: string }>(
    "SELECT id,status FROM hosting_assets WHERE id=ANY($1::uuid[])", [signals.map(signal => signal.id)]);
  const states = new Map(rows.rows.map(row => [row.id, row.status]));
  await clearJobSignals(signals.filter(signal => {
    const status = states.get(signal.id);
    return status ? ["ready", "failed", "revoked"].includes(status) : Date.now() - signal.modifiedAt.getTime() > 3_600_000;
  }).map(signal => signal.id));
}

async function main() {
  assertHostingEnabled();
  if (process.argv.includes("--once")) {
    await cleanupExpired();
    await processNext();
    return;
  }
  const stop = new AbortController();
  const workers = await Promise.allSettled([true, false].map(async (maintenanceEnabled) => {
    try { await run({ maintenanceEnabled, signal: stop.signal }); }
    catch (error) { stop.abort(); throw error; }
  }));
  const failure = workers.find((worker) => worker.status === "rejected");
  if (failure?.status === "rejected") throw failure.reason;
}

async function run({ maintenanceEnabled, signal }: { maintenanceEnabled: boolean; signal: AbortSignal }) {
  let nextMaintenance = 0;
  let draining = false;
  do {
    const signals = await pendingJobSignals();
    const maintenance = maintenanceEnabled && Date.now() >= nextMaintenance;
    if (maintenance) {
      await cleanupExpired();
      nextMaintenance = Date.now() + 30 * 60_000;
    }
    const processed: boolean = (draining || maintenance || signals.length > 0) && await processNext();
    draining = processed;
    if (!processed) await clearCompletedSignals(signals);
    if (!processed) await setTimeout(5000, undefined, { signal });
  } while (!signal.aborted);
}

main().catch((error) => { console.error(error instanceof Error ? error.message : "Hosting worker failed."); process.exitCode = 1; })
  .finally(() => hostingPool().end());

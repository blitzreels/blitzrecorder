import { setTimeout } from "node:timers/promises";
import { checkNext, cleanupExpired, processNext } from "../lib/hosting/processor";
import { migrate } from "../lib/hosting/migrate";
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
  const applied = await migrate(new URL("../migrations/", import.meta.url));
  if (applied.length) console.log(`Applied ${applied.join(", ")}`);
  let nextMaintenance = 0;
  let draining = false;
  do {
    const signals = await pendingJobSignals();
    const maintenance = Date.now() >= nextMaintenance;
    if (maintenance) {
      await cleanupExpired();
      nextMaintenance = Date.now() + 30 * 60_000;
    }
    const processed: boolean = (draining || maintenance || signals.length > 0) && (await processNext() || await checkNext());
    draining = processed;
    if (!processed) await clearCompletedSignals(signals);
    if (process.argv.includes("--once")) break;
    if (!processed) await setTimeout(5000);
  } while (true);
}

main().catch((error) => { console.error(error instanceof Error ? error.message : "Hosting worker failed."); process.exitCode = 1; })
  .finally(() => hostingPool().end());

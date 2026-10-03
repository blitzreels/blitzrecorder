import { Pool, type PoolClient } from "pg";
import { required } from "./model";

const state = globalThis as typeof globalThis & { hostingPool?: Pool };

export function hostingPool(): Pool {
  const connectionString = required("HOSTING_DATABASE_URL");
  state.hostingPool ??= new Pool({
    connectionString, max: 4, idleTimeoutMillis: 20_000, connectionTimeoutMillis: 15_000, query_timeout: 30_000,
    ssl: ["localhost", "127.0.0.1", "[::1]"].includes(new URL(connectionString).hostname) ? false : true,
  });
  return state.hostingPool;
}

let listedColumn: Promise<void> | null = null;

/** Idempotent so a library deploy does not wait on a separate migration run. */
export function ensureListedColumn(): Promise<void> {
  listedColumn ??= hostingPool().query(
    "ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS listed BOOLEAN NOT NULL DEFAULT true",
  ).then(() => undefined);
  return listedColumn;
}

export async function transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await hostingPool().connect();
  try {
    await client.query("BEGIN");
    const result = await operation(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

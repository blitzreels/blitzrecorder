import { createHash } from "node:crypto";
import { Pool } from "pg";

/**
 * Postgres-backed email capture for visitors who can't act now: people not on a
 * Mac, and the iPhone-app waitlist. Optional, exactly like the license store:
 * with no POSTGRES_URL/DATABASE_URL configured every call is a graceful no-op,
 * so local dev and previews never error.
 */

function connectionString(): string | null {
  // `||` (not `??`): an empty-string env var means "unconfigured", same as unset.
  return process.env.POSTGRES_URL || process.env.DATABASE_URL || null;
}

export function isNotifyStoreConfigured(): boolean {
  return connectionString() !== null;
}

const globalStore = globalThis as typeof globalThis & {
  __brnPool?: Pool;
  __brnSchemaReady?: Promise<void>;
};

function getPool(): Pool {
  const url = connectionString();
  if (!url) {
    throw new Error("Notify store is not configured (missing POSTGRES_URL)");
  }
  globalStore.__brnPool ??= new Pool({
    connectionString: url,
    ssl: /localhost|127\.0\.0\.1/.test(url) ? undefined : true,
    max: 2,
    idleTimeoutMillis: 30_000,
  });
  return globalStore.__brnPool;
}

function ensureSchema(): Promise<void> {
  globalStore.__brnSchemaReady ??= getPool()
    .query(
      `CREATE TABLE IF NOT EXISTS blitzrecorder_notify_signups (
         id BIGSERIAL PRIMARY KEY,
         email TEXT NOT NULL,
         source TEXT,
         os TEXT,
         attribution JSONB NOT NULL DEFAULT '{}'::jsonb,
         created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
         UNIQUE (email, source)
       );
       CREATE TABLE IF NOT EXISTS blitzrecorder_download_emails (
         email TEXT PRIMARY KEY,
         sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
       );
       ALTER TABLE blitzrecorder_download_emails ADD COLUMN IF NOT EXISTS network_hash TEXT;
       CREATE INDEX IF NOT EXISTS blitzrecorder_download_emails_network
         ON blitzrecorder_download_emails (network_hash, sent_at);`,
    )
    .then(() => undefined)
    .catch((error) => {
      globalStore.__brnSchemaReady = undefined;
      throw error;
    });
  return globalStore.__brnSchemaReady;
}

export type NotifySignup = {
  email: string;
  source: string;
  os?: string | null;
  attribution?: Record<string, string>;
};

export type NotifySignupResult = "unconfigured" | "new" | "repeat";

/** `new` the first time this email signs up from this source, `repeat` after that. */
export async function recordNotifySignup(signup: NotifySignup): Promise<NotifySignupResult> {
  if (!isNotifyStoreConfigured()) {
    return "unconfigured";
  }
  await ensureSchema();
  const result = await getPool().query<{ inserted: boolean }>(
    `INSERT INTO blitzrecorder_notify_signups (email, source, os, attribution)
     VALUES ($1, $2, $3, $4::jsonb)
     ON CONFLICT (email, source) DO UPDATE SET
       os = EXCLUDED.os,
       attribution = EXCLUDED.attribution
     RETURNING (xmax = 0) AS inserted`,
    [
      signup.email,
      signup.source,
      signup.os ?? null,
      JSON.stringify(signup.attribution ?? {}),
    ],
  );
  return result.rows[0]?.inserted ? "new" : "repeat";
}

/** Download emails one network may trigger per hour, so a script can't send to a list of strangers. */
const DOWNLOAD_EMAILS_PER_NETWORK_HOUR = 5;

/**
 * Reserves the one download-link email an address may ever get. `claimed` means send now; release the
 * claim if the send fails so the visitor can retry. Keyed on the lowercased address, not the form source.
 */
export async function claimDownloadEmail({ email, network }: { email: string; network: string }):
  Promise<"claimed" | "already_sent" | "limited" | "unconfigured"> {
  if (!isNotifyStoreConfigured()) return "unconfigured";
  await ensureSchema();
  const networkHash = createHash("sha256").update(`download-email:${network}`).digest("hex");
  const client = await getPool().connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`download-email:${networkHash}`]);
    const recent = await client.query<{ count: string }>(
      "SELECT count(*) FROM blitzrecorder_download_emails WHERE network_hash = $1 AND sent_at > now() - interval '1 hour'",
      [networkHash]);
    if (Number(recent.rows[0]?.count ?? 0) >= DOWNLOAD_EMAILS_PER_NETWORK_HOUR) {
      await client.query("ROLLBACK");
      return "limited";
    }
    const result = await client.query(
      `INSERT INTO blitzrecorder_download_emails (email, network_hash) VALUES ($1, $2)
       ON CONFLICT DO NOTHING RETURNING email`, [email, networkHash]);
    await client.query("COMMIT");
    return result.rowCount ? "claimed" : "already_sent";
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function releaseDownloadEmail(email: string): Promise<void> {
  await getPool().query("DELETE FROM blitzrecorder_download_emails WHERE email = $1", [email]);
}

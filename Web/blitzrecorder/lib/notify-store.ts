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
       );`,
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

/** Returns true when the lead was persisted, false when the store is unconfigured. */
export async function recordNotifySignup(signup: NotifySignup): Promise<boolean> {
  if (!isNotifyStoreConfigured()) {
    return false;
  }
  await ensureSchema();
  await getPool().query(
    `INSERT INTO blitzrecorder_notify_signups (email, source, os, attribution)
     VALUES ($1, $2, $3, $4::jsonb)
     ON CONFLICT (email, source) DO UPDATE SET
       os = EXCLUDED.os,
       attribution = EXCLUDED.attribution`,
    [
      signup.email,
      signup.source,
      signup.os ?? null,
      JSON.stringify(signup.attribution ?? {}),
    ],
  );
  return true;
}

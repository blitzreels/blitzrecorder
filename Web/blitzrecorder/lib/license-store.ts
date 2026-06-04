import { Pool } from "pg";
import type { LicensePayload } from "./licenses";

/**
 * Postgres-backed license records. Optional: when no POSTGRES_URL/DATABASE_URL
 * is configured, every caller skips the store and the system behaves exactly
 * like the stateless Stripe-only flow.
 *
 * The store adds what stateless keys cannot do on their own:
 * - a customer/license table you can query,
 * - manual revocation (`status = 'revoked'`) without refunding,
 * - instant kill on `charge.refunded` / `charge.dispute.created` webhooks.
 *
 * Stripe stays the source of truth for payment state; this table is the
 * source of truth for revocation.
 */

export type StoredLicense = {
  licenseId: string;
  email: string;
  stripeSessionId: string;
  stripePaymentIntentId: string | null;
  stripeCustomerId: string | null;
  stripePriceId: string;
  status: "active" | "revoked";
  revokedReason: string | null;
  issuedAt: Date;
};

export type StoredPaymentIntentRevocation = {
  paymentIntentId: string;
  reason: string;
};

function connectionString(): string | null {
  return process.env.POSTGRES_URL ?? process.env.DATABASE_URL ?? null;
}

export function isLicenseStoreConfigured(): boolean {
  return connectionString() !== null;
}

// Reuse one pool across hot reloads / route invocations within an instance.
const globalStore = globalThis as typeof globalThis & {
  __brlPool?: Pool;
  __brlSchemaReady?: Promise<void>;
};

function getPool(): Pool {
  const url = connectionString();
  if (!url) {
    throw new Error("License store is not configured (missing POSTGRES_URL)");
  }

  globalStore.__brlPool ??= new Pool({
    connectionString: url,
    // Hosted Postgres (Neon, Supabase, RDS) requires TLS; local dev does not.
    ssl: /localhost|127\.0\.0\.1/.test(url) ? undefined : true,
    max: 3,
    idleTimeoutMillis: 30_000,
  });
  return globalStore.__brlPool;
}

function ensureSchema(): Promise<void> {
  globalStore.__brlSchemaReady ??= getPool()
    .query(
      `CREATE TABLE IF NOT EXISTS blitzrecorder_licenses (
         license_id TEXT PRIMARY KEY,
         email TEXT NOT NULL,
         stripe_session_id TEXT NOT NULL UNIQUE,
         stripe_payment_intent_id TEXT,
         stripe_customer_id TEXT,
         stripe_price_id TEXT NOT NULL,
         status TEXT NOT NULL DEFAULT 'active',
         revoked_reason TEXT,
         issued_at TIMESTAMPTZ NOT NULL,
         created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
         updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
       );
       CREATE INDEX IF NOT EXISTS blitzrecorder_licenses_payment_intent_idx
         ON blitzrecorder_licenses (stripe_payment_intent_id);
       CREATE TABLE IF NOT EXISTS blitzrecorder_revoked_payment_intents (
         payment_intent_id TEXT PRIMARY KEY,
         reason TEXT NOT NULL,
         created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
         updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
       );`,
    )
    .then(() => undefined)
    .catch((error) => {
      // Let the next call retry instead of caching a failed init forever.
      globalStore.__brlSchemaReady = undefined;
      throw error;
    });
  return globalStore.__brlSchemaReady;
}

/**
 * Insert or refresh a license row. Never resurrects a revoked license: the
 * conflict update deliberately leaves `status`/`revoked_reason` untouched, so
 * post-validation backfills cannot undo a manual or webhook revocation.
 */
export async function upsertLicense(payload: LicensePayload): Promise<void> {
  await ensureSchema();
  const paymentIntentRevocation = payload.stripePaymentIntentId
    ? await getPaymentIntentRevocation(payload.stripePaymentIntentId)
    : null;
  const status = paymentIntentRevocation ? "revoked" : "active";
  const revokedReason = paymentIntentRevocation?.reason ?? null;

  await getPool().query(
    `INSERT INTO blitzrecorder_licenses
       (license_id, email, stripe_session_id, stripe_payment_intent_id,
        stripe_customer_id, stripe_price_id, status, revoked_reason, issued_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, to_timestamp($9))
     ON CONFLICT (license_id) DO UPDATE SET
       email = EXCLUDED.email,
       stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
       stripe_customer_id = EXCLUDED.stripe_customer_id,
       updated_at = now()`,
    [
      payload.licenseId,
      payload.email,
      payload.stripeSessionId,
      payload.stripePaymentIntentId,
      payload.stripeCustomerId,
      payload.stripePriceId,
      status,
      revokedReason,
      payload.issuedAt,
    ],
  );
}

type LicenseRow = {
  license_id: string;
  email: string;
  stripe_session_id: string;
  stripe_payment_intent_id: string | null;
  stripe_customer_id: string | null;
  stripe_price_id: string;
  status: string;
  revoked_reason: string | null;
  issued_at: Date;
};

function toStoredLicense(row: LicenseRow): StoredLicense {
  return {
    licenseId: row.license_id,
    email: row.email,
    stripeSessionId: row.stripe_session_id,
    stripePaymentIntentId: row.stripe_payment_intent_id,
    stripeCustomerId: row.stripe_customer_id,
    stripePriceId: row.stripe_price_id,
    status: row.status === "revoked" ? "revoked" : "active",
    revokedReason: row.revoked_reason,
    issuedAt: row.issued_at,
  };
}

export async function getLicense(licenseId: string): Promise<StoredLicense | null> {
  await ensureSchema();
  const result = await getPool().query<LicenseRow>(
    `SELECT * FROM blitzrecorder_licenses WHERE license_id = $1`,
    [licenseId],
  );
  const row = result.rows[0];
  return row ? toStoredLicense(row) : null;
}

export async function getPaymentIntentRevocation(
  paymentIntentId: string,
): Promise<StoredPaymentIntentRevocation | null> {
  await ensureSchema();
  const result = await getPool().query<{ payment_intent_id: string; reason: string }>(
    `SELECT payment_intent_id, reason
     FROM blitzrecorder_revoked_payment_intents
     WHERE payment_intent_id = $1`,
    [paymentIntentId],
  );
  const row = result.rows[0];
  return row ? { paymentIntentId: row.payment_intent_id, reason: row.reason } : null;
}

/** Returns the number of licenses revoked (0 when none matched). */
export async function revokeLicenseByPaymentIntent(
  paymentIntentId: string,
  reason: string,
): Promise<number> {
  await ensureSchema();
  await getPool().query(
    `INSERT INTO blitzrecorder_revoked_payment_intents (payment_intent_id, reason)
     VALUES ($1, $2)
     ON CONFLICT (payment_intent_id) DO UPDATE SET
       reason = EXCLUDED.reason,
       updated_at = now()`,
    [paymentIntentId, reason],
  );

  const result = await getPool().query(
    `UPDATE blitzrecorder_licenses
     SET status = 'revoked', revoked_reason = $2, updated_at = now()
     WHERE stripe_payment_intent_id = $1 AND status <> 'revoked'`,
    [paymentIntentId, reason],
  );
  return result.rowCount ?? 0;
}

/** Manual ops helper: revoke a single license by its id. */
export async function revokeLicenseById(licenseId: string, reason: string): Promise<number> {
  await ensureSchema();
  const result = await getPool().query(
    `UPDATE blitzrecorder_licenses
     SET status = 'revoked', revoked_reason = $2, updated_at = now()
     WHERE license_id = $1 AND status <> 'revoked'`,
    [licenseId, reason],
  );
  return result.rowCount ?? 0;
}

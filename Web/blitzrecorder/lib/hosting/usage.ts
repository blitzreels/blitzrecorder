import type { PoolClient } from "pg";
import { HOSTING_PLAN } from "./plan";

type Queryable = Pick<PoolClient, "query">;

/**
 * Bytes our hosting holds for the account. Videos in the owner's own Cloudflare account don't count. A failed video holds
 * only its source until cleanup; a removed one counts until its files are deleted.
 */
export async function storedBytes({ db, accountID }: { db: Queryable; accountID: string }): Promise<number> {
  const result = await db.query<{ bytes: string }>(
    `SELECT COALESCE(SUM(CASE WHEN stored_bytes > 0 THEN stored_bytes WHEN status = 'failed' THEN declared_bytes ELSE reserved_bytes END),0)::text
       AS bytes FROM hosting_assets WHERE account_id = $1 AND media_origin IS NULL`, [accountID]);
  return Number(result.rows[0].bytes);
}

/** Seconds of video uploaded in the plan's rolling window. */
export async function uploadedSeconds({ db, accountID }: { db: Queryable; accountID: string }): Promise<number> {
  const result = await db.query<{ seconds: number }>(
    "SELECT COALESCE(SUM(seconds),0) AS seconds FROM hosting_upload_usage WHERE account_id=$1 AND created_at>now()-$2*interval '1 day'",
    [accountID, HOSTING_PLAN.uploadWindowDays]);
  return Number(result.rows[0].seconds);
}

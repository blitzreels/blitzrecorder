import { cookies } from "next/headers";
import { hostingPool, ensureListedColumn } from "./db";
import { required, type AssetStatus, type HostingAccount } from "./model";
import { accountForToken } from "./account";
import { HOSTING_PLAN } from "./plan";

const secure = process.env.NODE_ENV === "production";

/** `__Host-` pins the cookie to this exact host over HTTPS; local http dev cannot use the prefix. */
export const SESSION_COOKIE = secure ? "__Host-br_hosting" : "br_hosting";
/** Matches the `hosting_connections.expires_at` default, so the cookie never outlives its token. */
export const SESSION_COOKIE_OPTIONS = { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 90 * 24 * 60 * 60 } as const;
export const SESSION_TOKEN = /^brh_[A-Za-z0-9_-]{43}$/;

export type LibraryVideo = {
  slug: string; title: string; status: AssetStatus; listed: boolean; duration: number | null; createdAt: string; poster: string | null;
};

export async function sessionToken(): Promise<string | null> {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  return token && SESSION_TOKEN.test(token) ? token : null;
}

export async function viewerAccount(): Promise<HostingAccount | null> {
  if (process.env.BLITZRECORDER_HOSTING_ENABLED !== "true") return null;
  const token = await sessionToken();
  return token ? accountForToken(token) : null;
}

/** Accounts that never subscribed have nothing paused; `deletesAt` is null once the retention window is unknown or over. */
export async function hostingStanding(account: HostingAccount): Promise<{ subscribed: boolean; deletesAt: Date | null }> {
  const row = (await hostingPool().query<{ subscribed: boolean; deletes_at: Date | null }>(
    `SELECT stripe_subscription_id IS NOT NULL AS subscribed,
       COALESCE(inactive_since, NULLIF(active_until, to_timestamp(0))) + $2::int * interval '1 day' AS deletes_at
     FROM hosting_accounts WHERE id=$1`, [account.id, HOSTING_PLAN.retentionDaysAfterExpiry])).rows[0];
  const deletesAt = row?.deletes_at && row.deletes_at.getTime() > Date.now() ? row.deletes_at : null;
  return { subscribed: Boolean(row?.subscribed), deletesAt };
}

/** Returns false when the video is not this account's or was already revoked. */
export async function stopSharingVideo({ account, slug }: { account: HostingAccount; slug: string }): Promise<boolean> {
  await ensureListedColumn();
  const result = await hostingPool().query(
    `UPDATE hosting_assets SET status='revoked', updated_at=now()
     WHERE slug=$1 AND account_id=$2 AND status IN ('queued','processing','ready','failed')`, [slug, account.id]);
  return Boolean(result.rowCount);
}

/** Turns the public link off or back on. The file stays hosted. */
export async function setVideoListing({ account, slug, listed }: { account: HostingAccount; slug: string; listed: boolean }): Promise<boolean> {
  await ensureListedColumn();
  const result = await hostingPool().query(
    `UPDATE hosting_assets SET listed=$3, updated_at=now()
     WHERE slug=$1 AND account_id=$2 AND status='ready'`, [slug, account.id, listed]);
  return Boolean(result.rowCount);
}

export async function ownerLibrary(account: HostingAccount): Promise<LibraryVideo[]> {
  await ensureListedColumn();
  const media = new URL(required("HOSTING_MEDIA_ORIGIN")).origin;
  const rows = await hostingPool().query<{
    slug: string; title: string; status: AssetStatus; listed: boolean; duration: number | null; declared_seconds: number; created_at: Date; has_poster: boolean;
  }>(`SELECT slug, title, status, listed, duration, declared_seconds, created_at, files @> '[{"path":"poster.jpg"}]'::jsonb AS has_poster
      FROM hosting_assets WHERE account_id=$1 AND status IN ('queued','processing','ready','failed') ORDER BY created_at DESC LIMIT 200`, [account.id]);
  return rows.rows.map((row) => ({
    slug: row.slug, title: row.title, status: row.status, listed: row.listed, duration: row.duration ?? row.declared_seconds,
    createdAt: row.created_at.toISOString(), poster: row.status === "ready" && row.listed && row.has_poster ? `${media}/s/${row.slug}/poster.jpg` : null,
  }));
}

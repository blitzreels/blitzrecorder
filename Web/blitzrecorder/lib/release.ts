// Server-only helper: reads the latest GitHub Release so the site can show the
// current version and link the DMG built by .github/workflows/macos-dmg.yml.
// Called from the root layout (Server Component); cached with hourly ISR so a
// new tag surfaces within the hour without a redeploy.

const OWNER = "blitzreels";
const REPO = "blitzrecorder";

export const GITHUB_REPO_URL = `https://github.com/${OWNER}/${REPO}`;
export const RELEASES_URL = `${GITHUB_REPO_URL}/releases`;
export const CHANGELOG_URL = `${GITHUB_REPO_URL}/blob/main/CHANGELOG.md`;
/** GitHub redirects this to the newest release (or the releases list if none). */
export const LATEST_RELEASE_URL = `${RELEASES_URL}/latest`;
/** Shown when no release is published yet; kept in sync by Scripts/set-version.py. */
export const FALLBACK_VERSION = "0.1.1";

export type Release = {
  /** Semver without the leading "v", e.g. "0.1.0". */
  version: string;
  /** Raw tag, e.g. "v0.1.0". */
  tag: string;
  /** Direct download URL of the macOS .dmg asset. */
  dmgUrl: string;
  /** GitHub release page. */
  htmlUrl: string;
  /** ISO date the release was published, or null. */
  publishedAt: string | null;
};

type GitHubAsset = { name: string; browser_download_url: string };
type GitHubRelease = {
  tag_name: string;
  html_url: string;
  published_at: string | null;
  assets: GitHubAsset[];
};

/**
 * Latest published release, or null when none exists / the repo is private /
 * the request fails. Callers fall back to the "Request access" state.
 * `/releases/latest` already excludes drafts and prereleases.
 */
export async function getLatestRelease(): Promise<Release | null> {
  try {
    // A token lets the API (and asset downloads) work while the repo is still
    // private. Set GITHUB_TOKEN in the deployment env; omit it once public.
    const token = process.env.GITHUB_TOKEN;
    const res = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        next: { revalidate: 3600 },
      },
    );
    if (!res.ok) return null;

    const data = (await res.json()) as GitHubRelease;
    const dmg = data.assets?.find((asset) => asset.name.toLowerCase().endsWith(".dmg"));
    if (!dmg || !data.tag_name) return null;

    return {
      version: data.tag_name.replace(/^v/i, ""),
      tag: data.tag_name,
      dmgUrl: dmg.browser_download_url,
      htmlUrl: data.html_url,
      publishedAt: data.published_at,
    };
  } catch {
    return null;
  }
}

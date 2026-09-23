// Client-safe release constants + the GitHub release lookup. Imported by both
// client components (constants/types) and the server layout (getLatestRelease),
// so it must stay free of Node built-ins. The self-hosted DMG fallback lives in
// the server-only root layout (app/layout.tsx).

const OWNER = "blitzreels";
const REPO = "blitzrecorder";

export const GITHUB_REPO_URL = `https://github.com/${OWNER}/${REPO}`;
export const RELEASES_URL = `${GITHUB_REPO_URL}/releases`;
/** GitHub redirects this to the newest release (or the releases list if none). */
export const LATEST_RELEASE_URL = `${RELEASES_URL}/latest`;
/** Unsigned tester installer: latest green CI on main (artifact windows-studio-installer-unsigned). */
export const WINDOWS_CI_WORKFLOW_URL = `${GITHUB_REPO_URL}/actions/workflows/ci.yml?query=is%3Asuccess+branch%3Amain`;
/** Shown when no release is published yet; kept in sync by Scripts/set-version.py. */
export const FALLBACK_VERSION = "0.21.0";

export type Release = {
  /** Semver without the leading "v", e.g. "0.1.0". */
  version: string;
  /** Raw tag, e.g. "v0.1.0". */
  tag: string;
  /** Direct download URL of the macOS .dmg asset. */
  dmgUrl: string;
  /** Direct download URL of the signed Windows installer, when present. */
  windowsUrl?: string;
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
 * Latest published release, or null when none exists or the request fails.
 * `/releases/latest` already excludes drafts and prereleases.
 */
export async function getLatestRelease(): Promise<Release | null> {
  try {
    const res = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/releases/latest?expected=${encodeURIComponent(FALLBACK_VERSION)}`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": "2022-11-28",
        },
        next: { revalidate: 3600 },
      },
    );
    if (!res.ok) return null;

    const data = (await res.json()) as GitHubRelease;
    const dmg = data.assets?.find((asset) => asset.name.toLowerCase().endsWith(".dmg"));
    const windows = data.assets?.find(
      (asset) => asset.name.toLowerCase() === "blitzrecorder-windows.exe",
    );
    if (!dmg || !data.tag_name) return null;

    return {
      version: data.tag_name.replace(/^v/i, ""),
      tag: data.tag_name,
      dmgUrl: dmg.browser_download_url,
      windowsUrl: windows?.browser_download_url,
      htmlUrl: data.html_url,
      publishedAt: data.published_at,
    };
  } catch {
    return null;
  }
}

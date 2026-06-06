/**
 * Build-time feature flags. NEXT_PUBLIC_* vars are inlined by Next.js at
 * build time, so flipping one requires a redeploy.
 *
 * OPEN_SOURCE gates everything that claims or links to public source code:
 * the octocat in the nav, the footer "Open source" column, the "View on
 * GitHub" button, and "open source" wording. The DMG download, version tag,
 * and release links stay live either way. Set NEXT_PUBLIC_OPEN_SOURCE=true
 * (Vercel env or .env.local) once the source repo is actually public.
 */
export const OPEN_SOURCE = process.env.NEXT_PUBLIC_OPEN_SOURCE === "true";

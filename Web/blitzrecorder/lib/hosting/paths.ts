/** Public routes. API stays under `/api/hosting`. Share links stay `/s/:slug` because the Mac app already issues them. */

export const videosPath = "/videos";
export const usagePath = "/videos/usage";
export const planPath = "/videos/plan";
export const accountPath = "/videos/account";
export const signInPath = "/sign-in";
export const billingPath = "/billing";

export const sharePath = (slug: string) => `/s/${slug}`;

/** Dashboard pages a signed-out visitor can be sent back to after signing in. */
export const dashboardPaths = [videosPath, usagePath, planPath, accountPath];

export const signInFor = (next: string) => `${signInPath}?next=${encodeURIComponent(next)}`;

/** Public routes. API stays under `/api/hosting`. Share links stay `/s/:slug` because the Mac app already issues them. */

export const videosPath = "/videos";
export const signInPath = "/sign-in";
export const billingPath = "/billing";

export const sharePath = (slug: string) => `/s/${slug}`;

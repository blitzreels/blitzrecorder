import type { AppLinks } from "@/components/hosting/app-shell";
import type { AccountOverview } from "@/lib/hosting/account";

export const previewLinks: AppLinks = {
  videos: "/videos/preview", usage: "/videos/preview/usage", plan: "/videos/preview/plan", account: "/videos/preview/account",
};

/** A mid-month subscriber. `?plan=none` on the plan preview shows a free account. */
export const previewOverview: AccountOverview = {
  email: "you@blitzrecorder.com", subscribed: true, activeUntil: "2026-11-14T00:00:00.000Z", storageLimit: 50_000_000_000,
  storedBytes: 12_400_000_000, uploadedSeconds: 4_320, sessions: 3,
};

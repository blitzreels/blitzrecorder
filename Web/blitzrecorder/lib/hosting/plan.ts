export const HOSTING_PLAN = {
  name: "BlitzRecorder Hosting",
  amount: 900,
  currency: "eur",
  interval: "month",
  taxBehavior: "exclusive",
  storageBytes: 50_000_000_000,
  uploadSeconds: 5 * 60 * 60,
  uploadWindowDays: 30,
  maximumResolution: 1080,
  retentionDaysAfterExpiry: 30,
} as const;

export function hostingPlan() {
  return { ...HOSTING_PLAN, available: process.env.BLITZRECORDER_HOSTING_ENABLED === "true" && Boolean(process.env.HOSTING_STRIPE_PRICE_ID) };
}

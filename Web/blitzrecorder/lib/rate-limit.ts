/**
 * Sliding-window limiter kept in memory, so each server instance counts on its
 * own. Good enough to stop a script from hammering Stripe through one route.
 */
export type RateLimiter = {
  /** Records a hit for `key` and returns false once the window is full. */
  allow: (key: string) => boolean;
};

const MAX_TRACKED_KEYS = 10_000;

export function createRateLimiter({ limit, windowMs }: { limit: number; windowMs: number }): RateLimiter {
  const hits = new Map<string, number[]>();

  return {
    allow(key) {
      const now = Date.now();
      const recent = (hits.get(key) ?? []).filter((at) => now - at < windowMs);
      if (recent.length >= limit) {
        hits.set(key, recent);
        return false;
      }
      recent.push(now);
      hits.delete(key);
      if (hits.size >= MAX_TRACKED_KEYS) {
        const oldest = hits.keys().next().value;
        if (oldest !== undefined) hits.delete(oldest);
      }
      hits.set(key, recent);
      return true;
    },
  };
}

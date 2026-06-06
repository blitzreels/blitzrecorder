/**
 * Always-on ambient lighting for the whole site. Fixed to the viewport so the
 * emerald aurora and grain stay consistent as you scroll. Section-specific
 * glows (hero, pricing) are layered locally on top of this.
 */
export function SiteBackground() {
  return (
    <div aria-hidden className="pointer-events-none fixed inset-0 -z-10">
      {/* top emerald aurora */}
      <div
        className="absolute inset-x-0 top-0 h-[54rem]"
        style={{
          background:
            "radial-gradient(62% 44% at 50% -10%, rgba(94,242,175,0.18), rgba(94,242,175,0.045) 38%, transparent 70%)",
        }}
      />
      {/* faint cool counter-light, upper right */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(38% 30% at 88% 14%, rgba(111,163,255,0.07), transparent 60%)",
        }}
      />
      {/* film grain */}
      <div className="br-grain absolute inset-0 opacity-[0.04] mix-blend-soft-light" />
      {/* settle back to pure background toward the fold bottom */}
      <div
        className="absolute inset-x-0 bottom-0 h-72"
        style={{ background: "linear-gradient(to top, #050807, transparent)" }}
      />
    </div>
  );
}

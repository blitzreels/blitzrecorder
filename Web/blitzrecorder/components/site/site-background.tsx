/**
 * Page grain only. Accent stays in type and controls, not a wash behind the fold.
 */
export function SiteBackground() {
  return (
    <div aria-hidden className="pointer-events-none fixed inset-0 -z-10">
      <div className="br-grain absolute inset-0 opacity-[0.04] mix-blend-soft-light" />
    </div>
  );
}

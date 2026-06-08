import type { ReactNode, SVGProps } from "react";
import type { FeatureIconKey } from "@/lib/content";

/**
 * Hand-rolled SVG icons so the site owns its iconography (no icon dependency).
 * Each renders a bare <svg> with no width/height, so callers size via className
 * (or the button's `[&_svg]:size-4` rule). Props spread last, so a caller can
 * override stroke width, etc.
 */
type IconProps = SVGProps<SVGSVGElement>;

function LineIcon({ children, ...props }: IconProps & { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      {...props}
    >
      {children}
    </svg>
  );
}

export function Check(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="M20 6 9 17l-5-5" />
    </LineIcon>
  );
}

export function Download(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="M12 3v12" />
      <path d="m7 10 5 5 5-5" />
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
    </LineIcon>
  );
}

export function ArrowUpRight(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="M7 17 17 7" />
      <path d="M7 7h10v10" />
    </LineIcon>
  );
}

export function ChevronDown(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="m6 9 6 6 6-6" />
    </LineIcon>
  );
}

export function Play(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden {...props}>
      <path d="M8.5 5.94c0-1.17 1.28-1.9 2.29-1.3l10.1 6.06c.98.59.98 2.01 0 2.6l-10.1 6.06c-1 .6-2.29-.13-2.29-1.3V5.94Z" />
    </svg>
  );
}

export function Close(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </LineIcon>
  );
}

export function CreditCard(props: IconProps) {
  return (
    <LineIcon {...props}>
      <rect x="2" y="5" width="20" height="14" rx="2" />
      <path d="M2 10h20" />
    </LineIcon>
  );
}

export function Copy(props: IconProps) {
  return (
    <LineIcon {...props}>
      <rect x="8" y="8" width="14" height="14" rx="2" />
      <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" />
    </LineIcon>
  );
}

/** Descriptive glyphs for the feature grid, one per capability. */
const featurePaths: Record<FeatureIconKey, ReactNode> = {
  // A display with an inset camera tile: screen + camera composited together.
  composite: (
    <>
      <rect x="2.5" y="4" width="19" height="13" rx="2" />
      <path d="M9 20.5h6" />
      <path d="M12 17v3.5" />
      <rect x="12.5" y="10" width="6.5" height="5" rx="1" />
    </>
  ),
  // Two frames with swap arrows: cut between layouts while recording.
  scenes: (
    <>
      <rect x="1.75" y="6.5" width="7" height="11" rx="1.5" />
      <rect x="15.25" y="6.5" width="7" height="11" rx="1.5" />
      <path d="M10 10.5h4" />
      <path d="m12.4 8.9 1.8 1.6-1.8 1.6" />
      <path d="M14 13.5h-4" />
      <path d="m11.6 11.9-1.8 1.6 1.8 1.6" />
    </>
  ),
  // A subject in frame with a separate backdrop element: replace the background.
  background: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <circle cx="12.5" cy="10.5" r="2.5" />
      <path d="M8.2 19.4a4.4 4.4 0 0 1 8.6 0" />
      <circle cx="6.7" cy="7.7" r="1.05" />
    </>
  ),
  // A phone with a pointer over it: control the iPhone from the Mac.
  remote: (
    <>
      <rect x="6.5" y="2.5" width="9" height="17" rx="2.5" />
      <path d="M10 5.3h2" />
      <path d="m13.2 12 6.3 2.3-2.6 1-1 2.6z" />
    </>
  ),
  // A tall frame crossed with a wide frame: vertical or horizontal.
  aspect: (
    <>
      <rect x="8" y="2.75" width="8" height="18.5" rx="1.5" />
      <rect x="2.75" y="8" width="18.5" height="8" rx="1.5" />
    </>
  ),
  // Two stacked sheets: separate source files kept after the take.
  sources: (
    <>
      <rect x="3.5" y="3.5" width="11.5" height="15" rx="2" />
      <rect x="9" y="7" width="11.5" height="15" rx="2" />
    </>
  ),
};

export function FeatureIcon({ name, ...props }: { name: FeatureIconKey } & IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      {...props}
    >
      {featurePaths[name]}
    </svg>
  );
}

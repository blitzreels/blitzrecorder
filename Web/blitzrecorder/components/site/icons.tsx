import type { ReactNode, SVGProps } from "react";

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

export function Key(props: IconProps) {
  return (
    <LineIcon {...props}>
      <circle cx="8" cy="15" r="4" />
      <path d="M11.5 12.5 21 3" />
      <path d="M17 3h4v4" />
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

export function ArrowRight(props: IconProps) {
  return (
    <LineIcon {...props}>
      <path d="M5 12h14" />
      <path d="m13 6 6 6-6 6" />
    </LineIcon>
  );
}

import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

type HeadingLevel = 1 | 2 | 3 | 4

const headingLevels: Record<HeadingLevel, string> = {
  1: "text-[clamp(2.75rem,8.5vw,5.75rem)] leading-[0.92] font-extrabold tracking-[-0.045em]",
  2: "text-[clamp(2.125rem,5vw,3.75rem)] leading-[0.98] font-extrabold tracking-[-0.04em]",
  3: "text-[1.375rem] leading-tight font-bold tracking-[-0.02em]",
  4: "text-lg leading-tight font-bold tracking-[-0.01em]",
}

function Heading({
  className,
  level = 2,
  as,
  ...props
}: React.ComponentProps<"h2"> & {
  level?: HeadingLevel
  /** Override the rendered element without changing the visual level. */
  as?: "h1" | "h2" | "h3" | "h4"
}) {
  const Tag = as ?? (`h${level}` as "h1" | "h2" | "h3" | "h4")
  return (
    <Tag
      data-slot="heading"
      className={cn(
        "font-display text-balance",
        headingLevels[level],
        className
      )}
      {...props}
    />
  )
}

const paragraphVariants = cva("", {
  variants: {
    tone: {
      default: "",
      muted: "text-muted-foreground",
      faint: "text-faint",
    },
    size: {
      sm: "text-sm leading-6",
      base: "text-base leading-7",
      lg: "text-[1.0625rem] leading-7 sm:text-lg sm:leading-8",
    },
  },
  defaultVariants: {
    tone: "muted",
    size: "lg",
  },
})

function Paragraph({
  className,
  tone,
  size,
  ...props
}: React.ComponentProps<"p"> & VariantProps<typeof paragraphVariants>) {
  return (
    <p
      data-slot="paragraph"
      className={cn(paragraphVariants({ tone, size }), className)}
      {...props}
    />
  )
}

export { Heading, Paragraph, headingLevels, paragraphVariants }
